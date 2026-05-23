//
//  S3BrowserService.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation
@preconcurrency import SotoS3

/// Concrete `S3Browsing` implementation backed by Soto. All methods
/// translate Soto-level errors into `S3BrowserError` before re-throwing
/// so callers never see provider-specific types.
struct S3BrowserService: S3Browsing {
    let factory: S3ClientFactory

    // MARK: - Buckets

    func listBuckets(account: S3Account) async throws -> [S3Bucket] {
        let s3 = try await factory.client(for: account)
        do {
            let response = try await s3.listBuckets()
            return (response.buckets ?? []).compactMap { bucket in
                guard let name = bucket.name else { return nil }
                return S3Bucket(
                    name: name,
                    createdAt: bucket.creationDate,
                    region: nil
                )
            }
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: - Objects

    func listObjects(
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

    func head(account: S3Account, bucket: String, key: String) async throws -> S3Object {
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

    func delete(account: S3Account, bucket: String, keys: [String]) async throws {
        guard !keys.isEmpty else { return }
        let s3 = try await factory.client(for: account)
        do {
            if keys.count == 1 {
                _ = try await s3.deleteObject(.init(bucket: bucket, key: keys[0]))
                return
            }
            let response = try await s3.deleteObjects(.init(
                bucket: bucket,
                delete: .init(objects: keys.map { .init(key: $0) })
            ))
            // `DeleteObjects` returns HTTP 200 even when individual keys fail.
            // The per-key failures arrive in `response.errors` — surface them
            // so the UI does not falsely report success.
            if let errors = response.errors, !errors.isEmpty {
                let summary = errors
                    .prefix(5)
                    .map { e in
                        let key = e.key ?? "?"
                        let code = e.code ?? "Error"
                        let msg = e.message ?? code
                        return "\(key): \(code) — \(msg)"
                    }
                    .joined(separator: "; ")
                let suffix = errors.count > 5 ? " (+\(errors.count - 5) more)" : ""
                throw S3BrowserError.providerError(
                    statusCode: 200,
                    message: summary + suffix
                )
            }
        } catch let error as S3BrowserError {
            throw error
        } catch {
            throw Self.map(error, bucket: bucket)
        }
    }

    /// Server-side single-request copy. Limited to source objects up to
    /// 5 GB; objects larger than that require `UploadPartCopy` and are
    /// out of v1 scope (tracked for v1.1 in the design spec).
    func copy(
        account: S3Account,
        fromBucket: String,
        fromKey: String,
        toBucket: String,
        toKey: String,
        metadata: [String: String]?
    ) async throws {
        let s3 = try await factory.client(for: account)
        do {
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

    func createFolder(account: S3Account, bucket: String, prefix: String) async throws {
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

    // MARK: - Helpers

    private static func unquote(_ s: String?) -> String {
        guard var s else { return "" }
        if s.hasPrefix("\"") { s.removeFirst() }
        if s.hasSuffix("\"") { s.removeLast() }
        return s
    }

    /// Map Soto errors into `S3BrowserError`. Prefers Soto's typed S3
    /// error surface (`S3ErrorType`, `AWSResponseError`), falling back
    /// to a low-confidence string match only for legacy paths.
    private static func map(_ error: Error, bucket: String? = nil, key: String? = nil) -> S3BrowserError {
        if let existing = error as? S3BrowserError { return existing }

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
            case "InvalidAccessKeyId",
                 "SignatureDoesNotMatch",
                 "ExpiredToken",
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
