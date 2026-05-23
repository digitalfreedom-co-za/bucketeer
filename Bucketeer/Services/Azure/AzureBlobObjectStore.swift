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
struct AzureBlobObjectStore: S3Browsing {
    let credentialsCache: AzureCredentialsCache
    let session: URLSession

    init(credentialsCache: AzureCredentialsCache, session: URLSession = .shared) {
        self.credentialsCache = credentialsCache
        self.session = session
    }

    // MARK: - S3Browsing

    func listBuckets(account: S3Account) async throws -> [S3Bucket] {
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

    func listObjects(
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

    func head(account: S3Account, bucket: String, key: String) async throws -> S3Object {
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

    func delete(account: S3Account, bucket: String, keys: [String]) async throws {
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

    func copy(
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
        if let metadata, !metadata.isEmpty {
            for (key, value) in metadata {
                request.setValue(value, forHTTPHeaderField: "x-ms-meta-" + key.lowercased())
            }
        }
        signer.sign(&request)

        _ = try await fetch(request: request, on: session, bucket: toBucket, key: toKey)
        // Server-side copy in Azure is asynchronous for large blobs —
        // status arrives via `x-ms-copy-status` on the response. v1 only
        // exposes Copy in the rename / move flows (small blobs), so we
        // accept the success response without polling. v1.1 will poll
        // when the status is `pending` for blobs > 256 MiB.
    }

    func createFolder(account: S3Account, bucket: String, prefix: String) async throws {
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

    // MARK: - Internal request helpers

    /// Fires the request, validates the HTTP status, returns the body
    /// for callers that need it.
    @discardableResult
    func fetch(
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
    static func testConnection(
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
