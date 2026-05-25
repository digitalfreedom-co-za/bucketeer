//
//  AzureBlobObjectStore.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation

/// `S3Browsing` implementation for Azure Blob Storage. Even though the
/// protocol is named after S3, every method has a semantically
/// equivalent Azure operation — listBuckets → list containers, listObjects
/// → list blobs with delimiter, etc. By implementing the same protocol
/// the rest of the app (browser view model, sync engine, file provider)
/// stays agnostic of the underlying transport.
public struct AzureBlobObjectStore: S3Browsing {
    public let credentialsCache: AzureCredentialsCache
    public let session: URLSession

    public init(credentialsCache: AzureCredentialsCache, session: URLSession = .shared) {
        self.credentialsCache = credentialsCache
        self.session = session
    }

    // MARK: - S3Browsing

    public func listBuckets(account: S3Account) async throws -> [S3Bucket] {
        let signer = try await credentialsCache.signer(for: account)
        let builder = AzureRequestBuilder(account: account)
        var request = URLRequest(url: builder.listContainersURL())
        request.httpMethod = "GET"
        signer.sign(&request)

        let data = try await fetch(request: request, on: session)
        let containers = try AzureListXMLParser.parseContainers(data)
        return containers.map { c in
            S3Bucket(name: c.name, createdAt: c.lastModified, region: nil)
        }
    }

    public func listObjects(
        account: S3Account,
        bucket: String,
        prefix: String,
        continuationToken: String?
    ) async throws -> S3Page {
        let signer = try await credentialsCache.signer(for: account)
        let builder = AzureRequestBuilder(account: account)
        var request = URLRequest(
            url: builder.listBlobsURL(
                container: bucket,
                prefix: prefix,
                marker: continuationToken
            )
        )
        request.httpMethod = "GET"
        signer.sign(&request)

        let data = try await fetch(request: request, on: session, bucket: bucket)
        let listing = try AzureListXMLParser.parseBlobs(data)

        let folders: [S3Object] = listing.prefixes.map { p in
            S3Object(
                key: p,
                size: 0,
                lastModified: Date.distantPast,
                etag: "",
                isFolder: true
            )
        }
        let files: [S3Object] = listing.blobs.compactMap { blob in
            guard !blob.name.hasSuffix("/") else { return nil }
            return S3Object(
                key: blob.name,
                size: blob.size,
                lastModified: blob.lastModified ?? Date.distantPast,
                etag: blob.etag ?? "",
                contentType: blob.contentType,
                storageClass: blob.accessTier,
                isFolder: false
            )
        }
        return S3Page(
            objects: folders + files,
            prefix: prefix,
            continuationToken: listing.nextMarker,
            hasMore: listing.nextMarker != nil
        )
    }

    public func head(account: S3Account, bucket: String, key: String) async throws -> S3Object {
        let signer = try await credentialsCache.signer(for: account)
        let builder = AzureRequestBuilder(account: account)
        var request = URLRequest(url: builder.blobPropertiesURL(container: bucket, blob: key))
        request.httpMethod = "HEAD"
        signer.sign(&request)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure HEAD returned a non-HTTP response.")
        }
        if let mapped = AzureBlobObjectStore.mapHTTP(
            http, body: nil, bucket: bucket, key: key
        ) {
            throw mapped
        }
        let size = (http.value(forHTTPHeaderField: "Content-Length")
            .flatMap { Int64($0) }) ?? 0
        let contentType = http.value(forHTTPHeaderField: "Content-Type")
        let etag = (http.value(forHTTPHeaderField: "ETag") ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let lastModified = http.value(forHTTPHeaderField: "Last-Modified")
            .flatMap(AzureListXMLParser.parseDate) ?? Date.distantPast
        let tier = http.value(forHTTPHeaderField: "x-ms-access-tier")
        return S3Object(
            key: key,
            size: size,
            lastModified: lastModified,
            etag: etag,
            contentType: contentType,
            storageClass: tier,
            isFolder: false
        )
    }

    public func delete(account: S3Account, bucket: String, keys: [String]) async throws {
        guard !keys.isEmpty else { return }
        let signer = try await credentialsCache.signer(for: account)
        let builder = AzureRequestBuilder(account: account)

        // Azure has no batch-delete endpoint — fire deletes sequentially.
        // Limiting to 4 in flight matches our S3 multipart parallelism and
        // keeps an account's throttling budget intact.
        var failures: [(key: String, error: Error)] = []
        try await withThrowingTaskGroup(of: (String, Error?).self) { group in
            let parallel = 4
            var iterator = keys.makeIterator()
            for _ in 0..<min(parallel, keys.count) {
                if let key = iterator.next() {
                    group.addTask {
                        do {
                            try await Self.deleteOne(
                                builder: builder,
                                signer: signer,
                                session: session,
                                bucket: bucket,
                                key: key
                            )
                            return (key, nil)
                        } catch {
                            return (key, error)
                        }
                    }
                }
            }
            while let result = try await group.next() {
                if let err = result.1 {
                    failures.append((key: result.0, error: err))
                }
                if let key = iterator.next() {
                    group.addTask {
                        do {
                            try await Self.deleteOne(
                                builder: builder,
                                signer: signer,
                                session: session,
                                bucket: bucket,
                                key: key
                            )
                            return (key, nil)
                        } catch {
                            return (key, error)
                        }
                    }
                }
            }
        }
        if !failures.isEmpty {
            let summary = failures.prefix(5).map { f in
                let reason = (f.error as? BucketeerError)?.errorDescription
                    ?? f.error.localizedDescription
                return "\(f.key): \(reason)"
            }.joined(separator: "; ")
            let extra = failures.count > 5 ? " (+\(failures.count - 5) more)" : ""
            throw BucketeerError.providerError(
                statusCode: 207,
                message: summary + extra
            )
        }
    }

    /// Maximum total wait for an asynchronous Azure copy before we
    /// give up and throw `.providerError(statusCode: 504)`. Tuned
    /// generously enough that the cross-storage-account copy of a
    /// few-GB blob fits comfortably; small-blob copies finish
    /// synchronously and never enter the poll loop at all.
    private static let copyPollTimeoutSeconds: TimeInterval = 30 * 60

    /// Initial backoff between Get-Blob-Properties polls. Doubles on
    /// every iteration up to `copyPollMaxIntervalSeconds`.
    private static let copyPollInitialIntervalSeconds: TimeInterval = 1.0
    private static let copyPollMaxIntervalSeconds: TimeInterval = 30.0

    public func copy(
        account: S3Account,
        fromBucket: String,
        fromKey: String,
        toBucket: String,
        toKey: String,
        metadata: [String: String]?
    ) async throws {
        let signer = try await credentialsCache.signer(for: account)
        let builder = AzureRequestBuilder(account: account)

        var request = URLRequest(url: builder.blobURL(container: toBucket, blob: toKey))
        request.httpMethod = "PUT"
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        request.setValue(
            builder.absoluteBlobURL(container: fromBucket, blob: fromKey).absoluteString,
            forHTTPHeaderField: "x-ms-copy-source"
        )
        // Codex R4 (high): copy(...) previously bypassed the
        // header sanitisation that saveMetadata uses. Same
        // hardening here so a hostile metadata value can't fold a
        // CR/LF into the outbound request.
        if let metadata, !metadata.isEmpty {
            for (key, value) in metadata {
                let lowerKey = key.lowercased()
                guard AzureRequestBuilder.isValidHeaderToken(lowerKey) else { continue }
                request.setValue(
                    AzureRequestBuilder.sanitiseHeaderValue(value),
                    forHTTPHeaderField: "x-ms-meta-" + lowerKey
                )
            }
        }
        signer.sign(&request)

        // Azure responds 202 Accepted with `x-ms-copy-status: pending`
        // for asynchronous copies (large blobs, cross-storage-account,
        // some sovereign cloud setups). Inspect the response and poll
        // Get Blob Properties on the destination until the copy
        // finishes — Codex blocker #1: the previous "fire and assume
        // success" path caused the rename / move flow to delete the
        // source while the copy was still pending, losing data.
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure Copy Blob returned a non-HTTP response.")
        }
        if let mapped = AzureBlobObjectStore.mapHTTP(http, body: nil, bucket: toBucket, key: toKey) {
            throw mapped
        }
        let initialStatus = http.value(forHTTPHeaderField: "x-ms-copy-status") ?? "success"
        switch initialStatus.lowercased() {
        case "success":
            return
        case "pending":
            try await waitForCopyToFinish(
                account: account,
                builder: builder,
                signer: signer,
                container: toBucket,
                key: toKey
            )
        case let other:
            throw BucketeerError.providerError(
                statusCode: http.statusCode,
                message: "Azure copy returned status \(other)."
            )
        }
    }

    /// Poll the destination blob's Get Blob Properties until
    /// `x-ms-copy-status` resolves to a terminal state. Exponential
    /// backoff (1s → 2s → 4s → … capped at 30s) bounded by
    /// `copyPollTimeoutSeconds`.
    private func waitForCopyToFinish(
        account: S3Account,
        builder: AzureRequestBuilder,
        signer: AzureSharedKeySigner,
        container: String,
        key: String
    ) async throws {
        let deadline = Date().addingTimeInterval(Self.copyPollTimeoutSeconds)
        var interval = Self.copyPollInitialIntervalSeconds
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            try Task.checkCancellation()

            var head = URLRequest(url: builder.blobPropertiesURL(container: container, blob: key))
            head.httpMethod = "HEAD"
            signer.sign(&head)
            let (_, response) = try await session.data(for: head)
            guard let http = response as? HTTPURLResponse else {
                throw BucketeerError.unknown(message: "Azure copy poll returned a non-HTTP response.")
            }
            if let mapped = AzureBlobObjectStore.mapHTTP(http, body: nil, bucket: container, key: key) {
                throw mapped
            }
            let status = http.value(forHTTPHeaderField: "x-ms-copy-status")?.lowercased() ?? "pending"
            switch status {
            case "success":
                return
            case "pending":
                interval = min(interval * 2, Self.copyPollMaxIntervalSeconds)
                continue
            case "failed", "aborted":
                let description = http.value(forHTTPHeaderField: "x-ms-copy-status-description") ?? status
                throw BucketeerError.providerError(
                    statusCode: http.statusCode,
                    message: "Azure copy \(status): \(description)"
                )
            default:
                throw BucketeerError.providerError(
                    statusCode: http.statusCode,
                    message: "Azure copy reported unexpected status \(status)."
                )
            }
        }
        throw BucketeerError.providerError(
            statusCode: 504,
            message: "Azure copy did not finish within \(Int(Self.copyPollTimeoutSeconds))s."
        )
    }

    public func createFolder(account: S3Account, bucket: String, prefix: String) async throws {
        let signer = try await credentialsCache.signer(for: account)
        let builder = AzureRequestBuilder(account: account)
        let key = prefix.hasSuffix("/") ? prefix : prefix + "/"

        var request = URLRequest(url: builder.blobURL(container: bucket, blob: key))
        request.httpMethod = "PUT"
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
        signer.sign(&request)

        _ = try await fetch(request: request, on: session, bucket: bucket, key: key)
    }

    // MARK: - Presigned URLs (Phase 9.9)

    /// Build a Service-SAS URL for the blob. Loads the storage account
    /// name + key out of the Keychain via `AzureCredentialsCache`,
    /// then hands them to `AzureSASBuilder`. The signature is computed
    /// locally; no network call is made.
    public func presignedDownloadURL(
        account: S3Account,
        bucket: String,
        key: String,
        ttl: TimeInterval
    ) async throws -> URL {
        // Reach into the cache to get the raw account name + key so we
        // can build the SAS independently of the request-signing pipeline.
        let credentials = try await credentialsCache.rawCredentials(for: account)
        guard let sas = AzureSASBuilder(
            accountName: credentials.accountName,
            base64AccountKey: credentials.base64AccountKey
        ) else {
            throw BucketeerError.authenticationFailed
        }
        let builder = AzureRequestBuilder(account: account)
        guard let url = sas.presignedDownloadURL(
            baseURL: builder.baseURL,
            container: bucket,
            blob: key,
            ttl: max(60, min(ttl, 7 * 24 * 60 * 60))
        ) else {
            throw BucketeerError.unknown(message: "Failed to construct Azure SAS URL.")
        }
        return url
    }

    // MARK: - Versioning (Phase 13.6 — Azure snapshots parity)
    //
    // Azure expresses object history as **snapshots**: time-stamped
    // read-only copies of the blob. We map them onto the same
    // `ObjectVersion` shape S3 uses, stuffing the snapshot timestamp
    // into `versionId`. Restore is a Copy-Blob from the snapshot URL
    // onto the live blob; delete-version removes a single snapshot.

    public func listVersions(
        account: S3Account,
        bucket: String,
        key: String
    ) async throws -> [ObjectVersion] {
        let signer = try await credentialsCache.signer(for: account)
        let builder = AzureRequestBuilder(account: account)
        var request = URLRequest(url: builder.listSnapshotsURL(container: bucket, blob: key))
        request.httpMethod = "GET"
        signer.sign(&request)
        let data = try await fetch(request: request, on: session, bucket: bucket, key: key)
        let listing = try AzureListXMLParser.parseBlobs(data)
        // Two pieces of state to merge: the live blob (snapshot == nil)
        // and zero or more snapshots. `isLatest` is true exactly when
        // `snapshot == nil`. We filter to the exact key — `prefix=`
        // can match neighbours that share a path component.
        let matching = listing.blobs.filter { $0.name == key }
        let versions: [ObjectVersion] = matching.map { blob in
            ObjectVersion(
                key: blob.name,
                versionId: blob.snapshot ?? "",
                isLatest: blob.snapshot == nil,
                isDeleteMarker: false,
                size: blob.size,
                lastModified: blob.lastModified ?? Date.distantPast,
                etag: blob.etag,
                storageClass: blob.accessTier
            )
        }
        return versions.sorted { $0.lastModified > $1.lastModified }
    }

    public func restoreVersion(
        account: S3Account,
        bucket: String,
        key: String,
        versionId: String
    ) async throws {
        // Azure restores by Copy-Blob from the snapshot URL onto the
        // live blob. The empty-versionId case means "live blob" —
        // no-op.
        guard !versionId.isEmpty else { return }
        let signer = try await credentialsCache.signer(for: account)
        let builder = AzureRequestBuilder(account: account)
        var request = URLRequest(url: builder.blobURL(container: bucket, blob: key))
        request.httpMethod = "PUT"
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        request.setValue(
            builder.snapshotSourceURL(container: bucket, blob: key, snapshot: versionId).absoluteString,
            forHTTPHeaderField: "x-ms-copy-source"
        )
        signer.sign(&request)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure snapshot restore returned a non-HTTP response.")
        }
        if let mapped = AzureBlobObjectStore.mapHTTP(http, body: nil, bucket: bucket, key: key) {
            throw mapped
        }
        // Codex R3 (medium): every non-`success`, non-`pending`
        // status was previously eaten by the default-success
        // branch — `failed` and `aborted` looked like wins.
        let status = (http.value(forHTTPHeaderField: "x-ms-copy-status") ?? "success").lowercased()
        switch status {
        case "success":
            return
        case "pending":
            try await waitForCopyToFinish(
                account: account, builder: builder, signer: signer,
                container: bucket, key: key
            )
        case "failed", "aborted":
            let description = http.value(forHTTPHeaderField: "x-ms-copy-status-description") ?? status
            throw BucketeerError.providerError(
                statusCode: http.statusCode,
                message: "Azure snapshot restore \(status): \(description)"
            )
        default:
            throw BucketeerError.providerError(
                statusCode: http.statusCode,
                message: "Azure snapshot restore returned unknown status \(status)."
            )
        }
    }

    public func deleteVersion(
        account: S3Account,
        bucket: String,
        key: String,
        versionId: String
    ) async throws {
        // Deleting the empty versionId would wipe the live blob —
        // refuse so callers can't fall through here when they meant
        // `delete(account:bucket:keys:)`.
        guard !versionId.isEmpty else {
            throw BucketeerError.unknown(
                message: "Cannot delete the live blob through deleteVersion — use delete(keys:) instead."
            )
        }
        let signer = try await credentialsCache.signer(for: account)
        let builder = AzureRequestBuilder(account: account)
        var request = URLRequest(url: builder.deleteSnapshotURL(container: bucket, blob: key, snapshot: versionId))
        request.httpMethod = "DELETE"
        // `x-ms-delete-snapshots = only` would error here because the
        // URL already targets a snapshot — leave it off.
        signer.sign(&request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure snapshot delete returned a non-HTTP response.")
        }
        if let mapped = AzureBlobObjectStore.mapHTTP(http, body: data, bucket: bucket, key: key) {
            throw mapped
        }
    }

    // MARK: - Metadata + tags (Phase 13.7 — Azure parity)
    //
    // Load: Get Blob Properties (HEAD) returns Content-Type +
    // Cache-Control + Content-Disposition + Content-Encoding +
    // x-ms-meta-* (user metadata) + x-ms-access-tier (storage class).
    // Tags come from a separate `?comp=tags` GET.
    //
    // Save: Set Blob Properties is the right RPC for the Content-*
    // headers, Set Blob Metadata for x-ms-meta-*, Set Blob Tags for
    // the tag XML. We collapse the four RPCs into one save call so
    // the editor stays simple; failures partway leave the previous
    // state visible to the user.
    public func loadMetadata(
        account: S3Account,
        bucket: String,
        key: String
    ) async throws -> ObjectMetadata {
        let signer = try await credentialsCache.signer(for: account)
        let builder = AzureRequestBuilder(account: account)

        var head = URLRequest(url: builder.blobPropertiesURL(container: bucket, blob: key))
        head.httpMethod = "HEAD"
        signer.sign(&head)
        let (_, headResponse) = try await session.data(for: head)
        guard let http = headResponse as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure HEAD for metadata returned a non-HTTP response.")
        }
        if let mapped = AzureBlobObjectStore.mapHTTP(http, body: nil, bucket: bucket, key: key) {
            throw mapped
        }

        // Build the user-metadata dictionary from every x-ms-meta-*
        // response header. Codex R3 (medium): refuse keys / values
        // that aren't safe to echo back into an outbound request,
        // so a hostile Azure response can't fold a CR/LF into the
        // next saveMetadata call.
        var userMetadata: [String: String] = [:]
        for (rawKey, value) in http.allHeaderFields {
            guard let stringKey = rawKey as? String,
                  let stringValue = value as? String else { continue }
            let lower = stringKey.lowercased()
            guard lower.hasPrefix("x-ms-meta-") else { continue }
            let metaKey = String(lower.dropFirst("x-ms-meta-".count))
            guard AzureRequestBuilder.isValidHeaderToken(metaKey) else { continue }
            userMetadata[metaKey] = AzureRequestBuilder.sanitiseHeaderValue(stringValue)
        }

        // Tags via a separate GET. Codex R3 (high): only treat a
        // 404 (`objectNotFound`) as "no tags". Re-throw every other
        // failure so a follow-up saveMetadata doesn't silently
        // overwrite real tags with the empty set.
        var tagRequest = URLRequest(url: builder.getBlobTagsURL(container: bucket, blob: key))
        tagRequest.httpMethod = "GET"
        signer.sign(&tagRequest)
        let tags: [String: String]
        do {
            let tagData = try await fetch(request: tagRequest, on: session, bucket: bucket, key: key)
            tags = AzureListXMLParser.parseTags(tagData)
        } catch let error as BucketeerError {
            if case .objectNotFound = error {
                tags = [:]
            } else {
                throw error
            }
        }

        return ObjectMetadata(
            contentType: http.value(forHTTPHeaderField: "Content-Type") ?? "",
            cacheControl: http.value(forHTTPHeaderField: "Cache-Control") ?? "",
            contentDisposition: http.value(forHTTPHeaderField: "Content-Disposition") ?? "",
            contentEncoding: http.value(forHTTPHeaderField: "Content-Encoding") ?? "",
            userMetadata: userMetadata,
            tags: tags,
            storageClass: http.value(forHTTPHeaderField: "x-ms-access-tier")
        )
    }

    public func saveMetadata(
        account: S3Account,
        bucket: String,
        key: String,
        metadata: ObjectMetadata
    ) async throws {
        let signer = try await credentialsCache.signer(for: account)
        let builder = AzureRequestBuilder(account: account)

        // 1) Set Blob Properties — Codex R3 (high #2). Without this
        //    RPC every HTTP-section edit (Content-Type, Cache-
        //    Control, Content-Disposition, Content-Encoding) was
        //    silently dropped because Set Metadata + Set Tags
        //    don't touch those fields. Azure uses `x-ms-blob-
        //    content-*` headers (not the bare HTTP headers).
        // Codex R4 (medium): Set Blob Properties **replaces** the
        // full property set — anything we don't pass gets wiped.
        // ObjectMetadata only models four fields, but Azure also
        // tracks Content-Language and Content-MD5. Re-read them
        // via HEAD and pass them back so an editor save doesn't
        // silently drop properties the user never touched.
        var preservedLanguage: String?
        var preservedMD5:      String?
        do {
            var head = URLRequest(url: builder.blobPropertiesURL(container: bucket, blob: key))
            head.httpMethod = "HEAD"
            signer.sign(&head)
            let (_, headResponse) = try await session.data(for: head)
            if let http = headResponse as? HTTPURLResponse {
                preservedLanguage = http.value(forHTTPHeaderField: "Content-Language")
                preservedMD5      = http.value(forHTTPHeaderField: "Content-MD5")
            }
        } catch {
            // Best-effort preservation; continue with the user's
            // edits even when HEAD fails.
        }

        var propsRequest = URLRequest(url: builder.setBlobPropertiesURL(container: bucket, blob: key))
        propsRequest.httpMethod = "PUT"
        propsRequest.setValue("0", forHTTPHeaderField: "Content-Length")
        var propertyHeaders: [(String, String)] = [
            ("x-ms-blob-content-type",        metadata.contentType),
            ("x-ms-blob-cache-control",       metadata.cacheControl),
            ("x-ms-blob-content-disposition", metadata.contentDisposition),
            ("x-ms-blob-content-encoding",    metadata.contentEncoding)
        ]
        if let lang = preservedLanguage, !lang.isEmpty {
            propertyHeaders.append(("x-ms-blob-content-language", lang))
        }
        if let md5 = preservedMD5, !md5.isEmpty {
            propertyHeaders.append(("x-ms-blob-content-md5", md5))
        }
        for (header, value) in propertyHeaders where !value.isEmpty {
            propsRequest.setValue(
                AzureRequestBuilder.sanitiseHeaderValue(value),
                forHTTPHeaderField: header
            )
        }
        signer.sign(&propsRequest)
        try await fireAndCheck(request: propsRequest, bucket: bucket, key: key)

        // 2) Set Blob Metadata — overwrites the entire x-ms-meta-*
        //    header set. An empty dict means "clear all". Keys are
        //    validated as HTTP tokens; values are CR/LF-stripped.
        var metaRequest = URLRequest(url: builder.setBlobMetadataURL(container: bucket, blob: key))
        metaRequest.httpMethod = "PUT"
        metaRequest.setValue("0", forHTTPHeaderField: "Content-Length")
        for (k, v) in metadata.userMetadata {
            let lowerKey = k.lowercased()
            guard AzureRequestBuilder.isValidHeaderToken(lowerKey) else { continue }
            metaRequest.setValue(
                AzureRequestBuilder.sanitiseHeaderValue(v),
                forHTTPHeaderField: "x-ms-meta-" + lowerKey
            )
        }
        signer.sign(&metaRequest)
        try await fireAndCheck(request: metaRequest, bucket: bucket, key: key)

        // 3) Set Blob Tags — overwrites the entire tag set with the
        //    supplied envelope. xmlEscape strips XML-illegal
        //    control scalars (Codex R3 low) before escaping.
        let body = AzureRequestBuilder.tagsXML(tags: metadata.tags)
        var tagRequest = URLRequest(url: builder.setBlobTagsURL(container: bucket, blob: key))
        tagRequest.httpMethod = "PUT"
        tagRequest.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        tagRequest.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        tagRequest.httpBody = body
        signer.sign(&tagRequest)
        try await fireAndCheck(request: tagRequest, bucket: bucket, key: key)
    }

    /// Small helper used by saveMetadata to send a request and bubble
    /// any non-2xx response through the standard `mapHTTP` path.
    private func fireAndCheck(request: URLRequest, bucket: String, key: String) async throws {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BucketeerError.unknown(
                message: "Azure metadata update returned a non-HTTP response."
            )
        }
        if let mapped = AzureBlobObjectStore.mapHTTP(http, body: data, bucket: bucket, key: key) {
            throw mapped
        }
    }

    // MARK: - Bucket insights (Phase 13.9)
    //
    // Azure lifecycle, CORS and access policies all live on the
    // **storage account** at the Azure Resource Manager (ARM)
    // management plane — a separate OAuth-authenticated API surface
    // from the Shared-Key-signed data plane Bucketeer talks to today.
    // Surfaced as a clear `featureNotSupported` until the OAuth
    // bring-up lands as its own phase (out of scope for v1).
    public func loadInsights(
        account: S3Account,
        bucket: String
    ) async throws -> BucketInsights {
        throw BucketeerError.featureNotSupported(
            featureKey: "bucket insights (Azure ARM management plane)"
        )
    }

    // MARK: - Internal request helpers

    /// Fires the request, validates the HTTP status, returns the body
    /// for callers that need it.
    @discardableResult
    public func fetch(
        request: URLRequest,
        on session: URLSession,
        bucket: String? = nil,
        key: String? = nil
    ) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw BucketeerError.cancelled
        } catch {
            throw Self.mapTransport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure response was not HTTP.")
        }
        if let mapped = AzureBlobObjectStore.mapHTTP(
            http, body: data, bucket: bucket, key: key
        ) {
            throw mapped
        }
        return data
    }

    private static func deleteOne(
        builder: AzureRequestBuilder,
        signer: AzureSharedKeySigner,
        session: URLSession,
        bucket: String,
        key: String
    ) async throws {
        var request = URLRequest(url: builder.deleteBlobURL(container: bucket, blob: key))
        request.httpMethod = "DELETE"
        request.setValue("include", forHTTPHeaderField: "x-ms-delete-snapshots")
        signer.sign(&request)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure DELETE returned a non-HTTP response.")
        }
        if let mapped = AzureBlobObjectStore.mapHTTP(
            http, body: nil, bucket: bucket, key: key
        ) {
            throw mapped
        }
    }

    // MARK: - Error mapping

    /// Returns a `BucketeerError` when the HTTP status indicates a
    /// failure, otherwise `nil` so the caller proceeds with the success
    /// path. The Azure `x-ms-error-code` header and the optional XML
    /// error envelope are both consulted.
    static func mapHTTP(
        _ http: HTTPURLResponse,
        body: Data?,
        bucket: String?,
        key: String?
    ) -> BucketeerError? {
        let status = http.statusCode
        if (200..<300).contains(status) { return nil }

        let headerCode = http.value(forHTTPHeaderField: "x-ms-error-code")
        let parsed = body.flatMap(AzureListXMLParser.parseError(_:))
        let code = headerCode ?? parsed?.code
        let message = parsed?.message
            ?? "HTTP \(status)\(code.map { " (\($0))" } ?? "")"

        switch code {
        case "ContainerNotFound":
            return .bucketNotFound(bucket ?? "?")
        case "BlobNotFound":
            return .objectNotFound(key: key ?? "?")
        case "AuthenticationFailed",
             "InvalidAuthenticationInfo",
             "AccountIsDisabled",
             "InsufficientAccountPermissions",
             "AuthorizationFailure":
            return .authenticationFailed
        case "ServerBusy", "OperationTimedOut":
            return .networkUnavailable
        default:
            break
        }
        switch status {
        case 401, 403: return .authenticationFailed
        case 404:
            if let key { return .objectNotFound(key: key) }
            if let bucket { return .bucketNotFound(bucket) }
            return .providerError(statusCode: status, message: message)
        default:
            return .providerError(statusCode: status, message: message)
        }
    }

    /// Map transport-layer errors (DNS, TLS, offline) into BucketeerError.
    static func mapTransport(_ error: Error) -> BucketeerError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed:
                return .providerError(
                    statusCode: 0,
                    message: String(
                        localized: "error.azure.dns",
                        defaultValue: "Could not resolve the Azure endpoint. Check the storage account name and any custom endpoint."
                    )
                )
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorTimedOut,
                 NSURLErrorNetworkConnectionLost:
                return .networkUnavailable
            default:
                break
            }
        }
        return .unknown(message: error.localizedDescription)
    }

    // MARK: - Connection test

    /// One-shot connection test used by the Add/Edit Account sheet. Calls
    /// the list-containers endpoint with throwaway credentials so the
    /// outcome reflects what a real listing would do without touching
    /// the credentials cache.
    public static func testConnection(
        account: S3Account,
        credentials: AccountCredentials,
        session: URLSession = .shared
    ) async throws {
        guard let signer = AzureCredentialsCache.makeSigner(
            account: account,
            credentials: credentials
        ) else {
            throw BucketeerError.authenticationFailed
        }
        let builder = AzureRequestBuilder(account: account)
        var request = URLRequest(url: builder.listContainersURL())
        request.httpMethod = "GET"
        signer.sign(&request)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Self.mapTransport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure response was not HTTP.")
        }
        if let mapped = Self.mapHTTP(http, body: data, bucket: nil, key: nil) {
            throw mapped
        }
    }
}
