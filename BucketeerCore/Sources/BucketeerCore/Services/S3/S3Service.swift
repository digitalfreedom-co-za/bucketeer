//
//  S3Service.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation
@preconcurrency import SotoS3
import NIOCore

/// Concrete `S3Browsing` implementation backed by Soto. All methods
/// translate Soto-level errors into `BucketeerError` before re-throwing
/// so callers never see provider-specific types.
public struct S3Service: S3Browsing {
    public let factory: S3ClientFactory

    public init(factory: S3ClientFactory) { self.factory = factory }

    // MARK: - Buckets

    public func listBuckets(account: S3Account) async throws -> [S3Bucket] {
        let s3 = try await factory.client(for: account)
        return try await Self.discoverBuckets(s3: s3, account: account)
    }

    /// ListBuckets, or a one-key listing of the account's named bucket
    /// (an error body, unlike HeadBucket, so a refusal can be told apart).
    static func discoverBuckets(s3: S3, account: S3Account) async throws -> [S3Bucket] {
        try await S3BucketDiscovery.buckets(
            for: account,
            listAll: {
                let response = try await s3.listBuckets()
                return (response.buckets ?? []).compactMap { bucket in
                    guard let name = bucket.name else { return nil }
                    return S3Bucket(
                        name: name,
                        createdAt: bucket.creationDate,
                        region: nil
                    )
                }
            },
            probe: { name in
                _ = try await s3.listObjectsV2(.init(bucket: name, maxKeys: 1))
            }
        )
    }

    // MARK: - Objects

    public func listObjects(
        account: S3Account,
        bucket: String,
        prefix: String,
        continuationToken: String?
    ) async throws -> S3Page {
        let s3 = try await factory.client(for: account)
        do {
            let response = try await s3.listObjectsV2(.init(
                bucket: bucket,
                continuationToken: continuationToken,
                delimiter: "/",
                prefix: prefix.isEmpty ? nil : prefix
            ))
            let folders: [S3Object] = (response.commonPrefixes ?? []).compactMap { cp in
                guard let folderPrefix = cp.prefix else { return nil }
                return S3Object(
                    key: folderPrefix,
                    size: 0,
                    lastModified: Date.distantPast,
                    etag: "",
                    isFolder: true
                )
            }
            let files: [S3Object] = (response.contents ?? []).compactMap { obj in
                guard let key = obj.key, !key.hasSuffix("/") else { return nil }
                return S3Object(
                    key: key,
                    size: obj.size ?? 0,
                    lastModified: obj.lastModified ?? Date.distantPast,
                    etag: Self.unquote(obj.eTag),
                    storageClass: obj.storageClass?.rawValue,
                    isFolder: false
                )
            }
            return S3Page(
                objects: folders + files,
                prefix: prefix,
                continuationToken: response.nextContinuationToken,
                hasMore: response.isTruncated ?? false
            )
        } catch {
            throw Self.map(error, bucket: bucket)
        }
    }

    public func head(account: S3Account, bucket: String, key: String) async throws -> S3Object {
        let s3 = try await factory.client(for: account)
        do {
            let response = try await s3.headObject(.init(bucket: bucket, key: key))
            return S3Object(
                key: key,
                size: response.contentLength ?? 0,
                lastModified: response.lastModified ?? Date.distantPast,
                etag: Self.unquote(response.eTag),
                contentType: response.contentType,
                storageClass: response.storageClass?.rawValue,
                isFolder: false
            )
        } catch {
            throw Self.map(error, key: key)
        }
    }

    /// S3 caps `DeleteObjects` at 1000 keys per request (per API spec).
    /// Chunk recursive deletes / large multi-selects accordingly —
    /// Without batching the operation would fail
    /// outright instead of completing in slices.
    private static let deleteObjectsBatchSize = 1000

    public func delete(account: S3Account, bucket: String, keys: [String]) async throws {
        guard !keys.isEmpty else { return }
        let s3 = try await factory.client(for: account)
        do {
            if keys.count == 1 {
                _ = try await s3.deleteObject(.init(bucket: bucket, key: keys[0]))
                return
            }
            // Aggregate per-key failures across all batches so the UI
            // shows a single comprehensive error if anything failed.
            var aggregatedErrors: [(key: String, code: String, message: String)] = []
            for batch in keys.chunked(by: Self.deleteObjectsBatchSize) {
                let response = try await s3.deleteObjects(.init(
                    bucket: bucket,
                    delete: .init(objects: batch.map { .init(key: $0) })
                ))
                if let errors = response.errors {
                    aggregatedErrors.append(contentsOf: errors.map { e in
                        (key: e.key ?? "?",
                         code: e.code ?? "Error",
                         message: e.message ?? e.code ?? "Error")
                    })
                }
            }
            if !aggregatedErrors.isEmpty {
                let summary = aggregatedErrors
                    .prefix(5)
                    .map { "\($0.key): \($0.code) — \($0.message)" }
                    .joined(separator: "; ")
                let suffix = aggregatedErrors.count > 5
                    ? " (+\(aggregatedErrors.count - 5) more)"
                    : ""
                throw BucketeerError.providerError(
                    statusCode: 200,
                    message: summary + suffix
                )
            }
        } catch let error as BucketeerError {
            throw error
        } catch {
            throw Self.map(error, bucket: bucket)
        }
    }

    /// Where the provider ignores `If-Match` on deletes, the ETag is
    /// compared with a HEAD right before an unconditional delete.
    public func delete(account: S3Account, bucket: String, key: String, ifMatch etag: String) async throws {
        let s3 = try await factory.client(for: account)
        let enforced = account.provider.conditionalRequests.contains(.deleteIfMatch)
        if !enforced {
            let current = try await Self.currentETag(s3: s3, bucket: bucket, key: key)
            try PreconditionCheck.verify(.ifMatch(etag), current: current, key: key)
        }
        do {
            _ = try await s3.deleteObject(.init(bucket: bucket, ifMatch: enforced ? ETag.quoted(etag) : nil, key: key))
        } catch where Self.isPreconditionFailure(error) {
            throw BucketeerError.preconditionFailed(key: key)
        } catch {
            throw Self.map(error, bucket: bucket, key: key)
        }
    }

    /// Server-side copy: one CopyObject, or ranged parts for objects
    /// above the provider's single-request limit (`S3MultipartCopy`).
    public func copy(
        account: S3Account,
        fromBucket: String,
        fromKey: String,
        toBucket: String,
        toKey: String,
        metadata: [String: String]?
    ) async throws {
        let s3 = try await factory.client(for: account)
        do {
            let head = try await head(account: account, bucket: fromBucket, key: fromKey)
            if S3MultipartCopy.needsParts(size: head.size, provider: account.provider) {
                let source = S3MultipartCopy.Source(bucket: fromBucket, key: fromKey, etag: head.etag,
                                                    size: head.size, metadata: metadata)
                _ = try await S3MultipartCopy.copy(source, toBucket: toBucket, toKey: toKey, ifAbsent: false,
                                                   enforced: account.provider.conditionalRequests,
                                                   copier: SotoObjectWriter(s3: s3))
                return
            }
            let source = "\(fromBucket)/\(fromKey)"
            let encodedSource = source.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) ?? source
            _ = try await s3.copyObject(.init(
                bucket: toBucket,
                copySource: encodedSource,
                key: toKey,
                metadata: metadata,
                metadataDirective: metadata != nil ? .replace : nil
            ))
        } catch {
            throw Self.map(error)
        }
    }

    /// Conditions the provider ignores on copies are checked with a HEAD
    /// of the source and the destination right before the copy.
    public func copyIfAbsent(account: S3Account, bucket: String, fromKey: String, sourceETag: String, toKey: String) async throws {
        let s3 = try await factory.client(for: account)
        let enforced = account.provider.conditionalRequests
        let source = "\(bucket)/\(fromKey)"
        do {
            let head = try await head(account: account, bucket: bucket, key: fromKey)
            try PreconditionCheck.verify(.ifMatch(sourceETag), current: head.etag, key: toKey)
            if S3MultipartCopy.needsParts(size: head.size, provider: account.provider) {
                _ = try await S3MultipartCopy.copy(
                    S3MultipartCopy.Source(bucket: bucket, key: fromKey, etag: sourceETag, size: head.size),
                    toBucket: bucket, toKey: toKey, ifAbsent: true, enforced: enforced,
                    copier: SotoObjectWriter(s3: s3)
                )
                return
            }
            if !enforced.contains(.copyIfAbsent) {
                let current = try await Self.currentETag(s3: s3, bucket: bucket, key: toKey)
                try PreconditionCheck.verify(.ifAbsent, current: current, key: toKey)
            }
            _ = try await s3.copyObject(.init(
                bucket: bucket,
                copySource: source.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? source,
                copySourceIfMatch: enforced.contains(.copySourceIfMatch) ? ETag.quoted(sourceETag) : nil,
                ifNoneMatch: enforced.contains(.copyIfAbsent) ? "*" : nil,
                key: toKey
            ))
        } catch where Self.isPreconditionFailure(error) {
            throw BucketeerError.preconditionFailed(key: toKey)
        } catch {
            throw Self.map(error, bucket: bucket, key: fromKey)
        }
    }

    public func createFolder(account: S3Account, bucket: String, prefix: String) async throws {
        let s3 = try await factory.client(for: account)
        let key = prefix.hasSuffix("/") ? prefix : prefix + "/"
        do {
            _ = try await s3.putObject(.init(
                bucket: bucket,
                contentLength: 0,
                key: key
            ))
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: - Presigned URLs (Phase 9.9)

    /// Soto exposes `signURL` on every AWSService — we use it to
    /// generate a Sig v4 signed GET URL that expires after the
    /// supplied interval. The signature is computed locally; no
    /// network call is made.
    ///
    /// Quirks worth noting:
    /// - Path-style vs virtual-host follows whatever `account.usesPathStyle`
    ///   resolved to in `S3ClientFactory.endpoint` — the URL we hand
    ///   to `signURL` is the same one the live request would hit.
    /// - The expiry is in `TimeAmount` (NIO) so we clamp the supplied
    ///   `TimeInterval` to a sane upper bound (7 days, the AWS Sig v4
    ///   maximum).
    public func presignedDownloadURL(
        account: S3Account,
        bucket: String,
        key: String,
        ttl: TimeInterval
    ) async throws -> URL {
        let s3 = try await factory.client(for: account)
        let url = Self.presignTargetURL(
            endpoint: S3ClientFactory.endpoint(for: account),
            bucket: bucket,
            key: key,
            virtualHost: Self.usesVirtualHost(account: account, bucket: bucket)
        )
        let clamped = max(60, min(ttl, 7 * 24 * 60 * 60))
        let expires = TimeAmount.seconds(Int64(clamped))
        do {
            return try await s3.signURL(
                url: url,
                httpMethod: .GET,
                expires: expires
            )
        } catch {
            throw Self.map(error)
        }
    }

    /// Object URL for signing, addressed like the account's requests:
    /// `signURL` skips Soto's S3 middleware, so it must be built here.
    /// Not every provider documents path-style (DigitalOcean Spaces
    /// does not). `appending(path:)` percent-encodes the raw key itself
    /// — encoding it beforehand produced `%2520` for a space.
    static func presignTargetURL(endpoint: URL, bucket: String, key: String, virtualHost: Bool) -> URL {
        guard virtualHost, var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              let host = components.host
        else { return endpoint.appending(path: "\(bucket)/\(key)") }
        components.host = "\(bucket).\(host)"
        return (components.url ?? endpoint).appending(path: key)
    }

    /// Soto's rule (S3Middleware): virtual-host for AWS and for
    /// `.s3ForceVirtualHost`, never for bucket names with a dot.
    static func usesVirtualHost(account: S3Account, bucket: String) -> Bool {
        (account.provider == .awsS3 || !account.usesPathStyle) && !bucket.contains(".")
    }

    // MARK: - Versioning (Phase 13.6)

    /// `ListObjectVersions` with prefix-matching on the requested key.
    /// We filter post-hoc to the exact key because S3 has no
    /// equivalent of "give me versions for one key only".
    public func listVersions(
        account: S3Account,
        bucket: String,
        key: String
    ) async throws -> [ObjectVersion] {
        let s3 = try await factory.client(for: account)
        do {
            var result: [ObjectVersion] = []
            var keyMarker: String? = nil
            var versionIdMarker: String? = nil
            // ListObjectVersions returns at most 1000 entries per call.
            // Objects with a longer history need the marker loop or the
            // UI silently shows a truncated version list. The page cap
            // bounds a misbehaving provider that always claims
            // isTruncated without advancing the markers.
            let pageCap = 50
            var pages = 0
            repeat {
                let response = try await s3.listObjectVersions(
                    .init(
                        bucket: bucket,
                        keyMarker: keyMarker,
                        prefix: key,
                        versionIdMarker: versionIdMarker
                    )
                )
                for entry in response.versions ?? [] where entry.key == key {
                    result.append(
                        ObjectVersion(
                            key: entry.key ?? key,
                            versionId: entry.versionId ?? "",
                            isLatest: entry.isLatest ?? false,
                            isDeleteMarker: false,
                            size: entry.size ?? 0,
                            lastModified: entry.lastModified ?? Date(),
                            etag: Self.unquote(entry.eTag),
                            storageClass: entry.storageClass?.rawValue
                        )
                    )
                }
                for marker in response.deleteMarkers ?? [] where marker.key == key {
                    result.append(
                        ObjectVersion(
                            key: marker.key ?? key,
                            versionId: marker.versionId ?? "",
                            isLatest: marker.isLatest ?? false,
                            isDeleteMarker: true,
                            size: 0,
                            lastModified: marker.lastModified ?? Date(),
                            etag: nil,
                            storageClass: nil
                        )
                    )
                }
                pages += 1
                if response.isTruncated == true, pages < pageCap {
                    keyMarker = response.nextKeyMarker
                    versionIdMarker = response.nextVersionIdMarker
                } else {
                    keyMarker = nil
                    versionIdMarker = nil
                }
            } while keyMarker != nil || versionIdMarker != nil
            // Sort newest-first so the latest version is at the top.
            result.sort { $0.lastModified > $1.lastModified }
            return result
        } catch {
            throw Self.map(error, bucket: bucket, key: key)
        }
    }

    /// Restore = server-side copy of the source version on top of
    /// itself, which becomes the new latest version. The original
    /// version is preserved.
    public func restoreVersion(
        account: S3Account,
        bucket: String,
        key: String,
        versionId: String
    ) async throws {
        let s3 = try await factory.client(for: account)
        // Encode key and version ID SEPARATELY. Percent-encoding the
        // whole string turns the `?` into %3F and S3 then looks up a
        // literal key named "key?versionId=…" — every versioned
        // restore 404s. The `?versionId=` separator must stay literal
        // per the x-amz-copy-source spec. Version IDs are opaque and
        // may contain query-significant characters (`+`, `/`, `=` on
        // some providers), so they get a strict query-value encoding.
        let encodedKey = key.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? key
        var queryValueAllowed = CharacterSet.alphanumerics
        queryValueAllowed.insert(charactersIn: "-._~")
        let encodedVersionId = versionId.addingPercentEncoding(
            withAllowedCharacters: queryValueAllowed
        ) ?? versionId
        let encodedSource = "\(bucket)/\(encodedKey)?versionId=\(encodedVersionId)"
        do {
            _ = try await s3.copyObject(.init(
                bucket: bucket,
                copySource: encodedSource,
                key: key,
                metadataDirective: .copy
            ))
        } catch {
            throw Self.map(error, bucket: bucket, key: key)
        }
    }

    public func deleteVersion(
        account: S3Account,
        bucket: String,
        key: String,
        versionId: String
    ) async throws {
        let s3 = try await factory.client(for: account)
        do {
            _ = try await s3.deleteObject(.init(
                bucket: bucket,
                key: key,
                versionId: versionId
            ))
        } catch {
            throw Self.map(error, bucket: bucket, key: key)
        }
    }

    // MARK: - Metadata + tags (Phase 13.7)

    /// HeadObject for `Content-*` + user metadata, GetObjectTagging
    /// for tags. Both fired in parallel.
    public func loadMetadata(
        account: S3Account,
        bucket: String,
        key: String
    ) async throws -> ObjectMetadata {
        let s3 = try await factory.client(for: account)
        do {
            async let headResponse = s3.headObject(.init(bucket: bucket, key: key))
            async let tagResponse = s3.getObjectTagging(.init(bucket: bucket, key: key))
            let head = try await headResponse
            let tagging = try await tagResponse
            var tags: [String: String] = [:]
            for entry in tagging.tagSet {
                tags[entry.key] = entry.value
            }
            return ObjectMetadata(
                contentType: head.contentType ?? "",
                cacheControl: head.cacheControl ?? "",
                contentDisposition: head.contentDisposition ?? "",
                contentEncoding: head.contentEncoding ?? "",
                userMetadata: head.metadata ?? [:],
                tags: tags,
                storageClass: head.storageClass?.rawValue
            )
        } catch {
            throw Self.map(error, bucket: bucket, key: key)
        }
    }

    /// CopyObject onto itself with `metadataDirective: .replace` to
    /// rewrite the HTTP + user metadata + content type, then a
    /// follow-up PutObjectTagging to replace the tag set. Both
    /// operations are independent so we don't roll the tag write
    /// back if the metadata write fails — the caller's UI surfaces
    /// the failure.
    public func saveMetadata(
        account: S3Account,
        bucket: String,
        key: String,
        metadata: ObjectMetadata
    ) async throws {
        let s3 = try await factory.client(for: account)
        let source = "\(bucket)/\(key)"
        let encodedSource = source.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? source
        let userMetadata = metadata.userMetadata.isEmpty ? nil : metadata.userMetadata
        do {
            _ = try await s3.copyObject(.init(
                bucket: bucket,
                cacheControl: metadata.cacheControl.isEmpty ? nil : metadata.cacheControl,
                contentDisposition: metadata.contentDisposition.isEmpty ? nil : metadata.contentDisposition,
                contentEncoding: metadata.contentEncoding.isEmpty ? nil : metadata.contentEncoding,
                contentType: metadata.contentType.isEmpty ? nil : metadata.contentType,
                copySource: encodedSource,
                key: key,
                metadata: userMetadata,
                metadataDirective: .replace,
                // A copy onto itself defaults to STANDARD; keep the
                // object's class so editing metadata does not move it.
                storageClass: metadata.storageClass.flatMap(S3.StorageClass.init(rawValue:))
            ))
        } catch {
            throw Self.map(error, bucket: bucket, key: key)
        }
        // PutObjectTagging — clears the existing set and replaces
        // with the supplied one.
        let tagSet: [S3.Tag] = metadata.tags.map { (k, v) in
            S3.Tag(key: k, value: v)
        }
        do {
            _ = try await s3.putObjectTagging(.init(
                bucket: bucket,
                key: key,
                tagging: S3.Tagging(tagSet: tagSet)
            ))
        } catch {
            throw Self.map(error, bucket: bucket, key: key)
        }
    }

    // MARK: - Bucket insights (Phase 13.9)

    /// Pull lifecycle + CORS + policy in parallel and stitch the
    /// results into a single `BucketInsights`. Each call is
    /// independently optional — providers commonly return
    /// `NoSuchLifecycleConfiguration` / `NoSuchCORSConfiguration` /
    /// `NoSuchBucketPolicy` when nothing is set, which we treat as
    /// empty rather than as an error.
    public func loadInsights(
        account: S3Account,
        bucket: String
    ) async throws -> BucketInsights {
        let s3 = try await factory.client(for: account)
        async let lifecycleTask = Self.safeLifecycle(s3: s3, bucket: bucket)
        async let corsTask = Self.safeCors(s3: s3, bucket: bucket)
        async let policyTask = Self.safePolicy(s3: s3, bucket: bucket)
        let lifecycle = await lifecycleTask
        let cors = await corsTask
        let policy = await policyTask
        return BucketInsights(
            bucket: bucket,
            lifecycleRules: lifecycle,
            corsRules: cors,
            policyJSON: policy
        )
    }

    private static func safeLifecycle(s3: S3, bucket: String) async -> [LifecycleRule] {
        do {
            let response = try await s3.getBucketLifecycleConfiguration(.init(bucket: bucket))
            return (response.rules ?? []).map { rule in
                let transitions: [String] = (rule.transitions ?? []).map { t in
                    let days = t.days.map { String($0) } ?? "?"
                    let cls = t.storageClass?.rawValue ?? "?"
                    return "after \(days) days → \(cls)"
                }
                var expirations: [String] = []
                if let exp = rule.expiration {
                    if let days = exp.days {
                        expirations.append("expire after \(days) days")
                    }
                    if let date = exp.date {
                        expirations.append("expire on \(date)")
                    }
                }
                if let nc = rule.noncurrentVersionExpiration?.noncurrentDays {
                    expirations.append("non-current expire after \(nc) days")
                }
                let filterPrefix = rule.filter.prefix
                return LifecycleRule(
                    id: rule.id ?? "(unnamed)",
                    prefix: filterPrefix,
                    enabled: rule.status == .enabled,
                    transitions: transitions,
                    expirations: expirations
                )
            }
        } catch {
            return []
        }
    }

    private static func safeCors(s3: S3, bucket: String) async -> [CORSRule] {
        do {
            let response = try await s3.getBucketCors(.init(bucket: bucket))
            return (response.corsRules ?? []).enumerated().map { (index, rule) in
                CORSRule(
                    id: rule.id ?? "rule-\(index)",
                    allowedOrigins: rule.allowedOrigins,
                    allowedMethods: rule.allowedMethods,
                    allowedHeaders: rule.allowedHeaders ?? [],
                    exposeHeaders: rule.exposeHeaders ?? [],
                    maxAgeSeconds: rule.maxAgeSeconds.map { Int($0) }
                )
            }
        } catch {
            return []
        }
    }

    private static func safePolicy(s3: S3, bucket: String) async -> String? {
        do {
            let response = try await s3.getBucketPolicy(.init(bucket: bucket))
            let raw = response.policy
            // Pretty-print so the read-only viewer shows formatted
            // JSON rather than a single line. Falls back to raw text
            // if parse fails.
            guard let data = raw.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let prettyData = try? JSONSerialization.data(
                    withJSONObject: object,
                    options: [.prettyPrinted, .sortedKeys]
                  ),
                  let prettyString = String(data: prettyData, encoding: .utf8) else {
                return raw
            }
            return prettyString
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private static func unquote(_ s: String?) -> String {
        guard var s else { return "" }
        if s.hasPrefix("\"") { s.removeFirst() }
        if s.hasSuffix("\"") { s.removeLast() }
        return s
    }

    /// True for an HTTP 412 answer to an If-Match / If-None-Match write,
    /// and for the 409 `ConditionalRequestConflict` S3 sends when a
    /// concurrent conditional write to the same key won.
    public static func isPreconditionFailure(_ error: Error) -> Bool {
        if case .preconditionFailed = error as? BucketeerError { return true }
        if let rawError = error as? AWSRawError {
            return rawError.context.responseCode.code == 412
        }
        if let awsError = error as? AWSErrorType {
            return awsError.context?.responseCode.code == 412
                || awsError.errorCode == "PreconditionFailed"
                || awsError.errorCode == "ConditionalRequestConflict"
        }
        return false
    }

    /// The `ifMatch` / `ifNoneMatch` header values for a PutObject;
    /// none for a condition the provider does not enforce.
    public static func headers(
        for precondition: WritePrecondition?,
        enforced: S3Provider.ConditionalRequests
    ) -> (ifMatch: String?, ifNoneMatch: String?) {
        switch precondition {
        case .ifMatch(let etag) where enforced.contains(.writeIfMatch): return (ETag.quoted(etag), nil)
        case .ifAbsent where enforced.contains(.writeIfAbsent): return (nil, "*")
        default: return (nil, nil)
        }
    }

    /// The object's ETag (unquoted), or `nil` when there is none.
    static func currentETag(s3: S3, bucket: String, key: String) async throws -> String? {
        do {
            return unquote(try await s3.headObject(.init(bucket: bucket, key: key)).eTag)
        } catch {
            // Mapped like `head`: a bare 404 is the object, not the bucket.
            let mapped = map(error, key: key)
            if case .objectNotFound = mapped { return nil }
            throw mapped
        }
    }

    /// Map Soto errors into `BucketeerError`. Prefers Soto's typed S3
    /// error surface (`S3ErrorType`, `AWSResponseError`), falling back
    /// to a low-confidence string match only for legacy paths.
    // Internal (not private): S3ResumableUploader shares the same
    // Soto-error → BucketeerError translation so the service-layer
    // contract holds on the multipart path too.
    /// `account` lets an unknown access key name the region it was
    /// tried in.
    static func map(
        _ error: Error,
        bucket: String? = nil,
        key: String? = nil,
        account: S3Account? = nil
    ) -> BucketeerError {
        if let existing = error as? BucketeerError { return existing }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError, urlError.code == .cancelled { return .cancelled }
        if isPreconditionFailure(error) { return .preconditionFailed(key: key ?? "?") }

        if let s3Error = error as? S3ErrorType {
            switch s3Error.errorCode {
            case S3ErrorType.noSuchBucket.errorCode:
                return .bucketNotFound(bucket ?? "?")
            case S3ErrorType.noSuchKey.errorCode,
                 S3ErrorType.notFound.errorCode:
                return .objectNotFound(key: key ?? "?")
            case S3ErrorType.accessDenied.errorCode:
                let status = Int(s3Error.context?.responseCode.code ?? 403)
                let message = s3Error.context?.message ?? "Access denied"
                return .providerError(statusCode: status, message: message)
            default:
                let status = Int(s3Error.context?.responseCode.code ?? 0)
                let message = s3Error.context?.message ?? s3Error.errorCode
                return .providerError(statusCode: status, message: message)
            }
        }

        if let rawError = error as? AWSRawError {
            let status = Int(rawError.context.responseCode.code)
            let body = (rawError.rawBody ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = String(body.prefix(240))
            let message = snippet.isEmpty
                ? "Server returned HTTP \(status) with an unrecognised response body."
                : "HTTP \(status): \(snippet)"
            if status == 401 || status == 403 {
                return .authenticationFailed
            }
            if status == 404 {
                if let bucket { return .bucketNotFound(bucket) }
                if let key { return .objectNotFound(key: key) }
            }
            return .providerError(statusCode: status, message: message)
        }

        if let awsError = error as? AWSErrorType {
            let status = Int(awsError.context?.responseCode.code ?? 0)
            let message = awsError.context?.message ?? awsError.errorCode
            switch awsError.errorCode {
            case "InvalidAccessKeyId":
                return .accessKeyNotRecognized(provider: account?.provider, region: account?.region)
            case "SignatureDoesNotMatch":
                return .secretKeyMismatch
            case "ExpiredToken",
                 "TokenRefreshRequired":
                return .authenticationFailed
            case "RequestTimeout", "SlowDown", "ServiceUnavailable":
                return .networkUnavailable
            default:
                return .providerError(statusCode: status, message: message)
            }
        }

        let nsError = error as NSError
        let combinedDescription = "\(nsError.domain) \(nsError.code) \(error.localizedDescription)"
        let isDNSFailure = combinedDescription.contains("NoSuchRecord")
            || combinedDescription.contains("CannotFindHost")
            || combinedDescription.contains("could not find host")
            || nsError.code == -65554
            || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCannotFindHost)
        if isDNSFailure {
            return .providerError(
                statusCode: 0,
                message: String(
                    localized: "error.dnsLookup",
                    defaultValue: "DNS lookup failed for the endpoint hostname. For non-AWS providers this usually means the bucket-as-subdomain URL is not served — enable Path-Style addressing in the account's Advanced settings."
                )
            )
        }

        if nsError.domain == NSURLErrorDomain || nsError.domain.hasPrefix("Network.") {
            return .networkUnavailable
        }

        return .unknown(message: error.localizedDescription)
    }
}
