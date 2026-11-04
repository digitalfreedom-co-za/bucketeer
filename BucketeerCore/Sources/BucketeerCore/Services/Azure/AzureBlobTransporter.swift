//
//  AzureBlobTransporter.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation

/// Upload / download counterpart to `AzureBlobObjectStore`. Lives in its
/// own file because the size-aware multipart paths get large and the
/// browser-only operations don't need to know about it.
///
/// Progress reporting calls back through the supplied `progress`
/// closure; the `TransferManager` wires it to the actor-isolated state
/// machine.
public struct AzureBlobTransporter: Sendable {
    public let credentialsCache: AzureCredentialsCache
    public let session: URLSession
    /// Optional bandwidth limiter charged per ranged GET / per block
    /// PUT / per single-shot PUT. Phase 13.2.
    public let limiter: BandwidthLimiter?

    /// Switch threshold between single-shot Put Block Blob and the
    /// staged Put Block + Put Block List path. Mirrors the S3 multipart
    /// threshold so users see consistent behaviour across providers.
    public static let multipartThreshold: Int64 = 5 * 1024 * 1024

    /// Preferred size of each staged block; matches the S3 part size.
    /// Azure allows up to 4000 MiB per block and 50 000 blocks per blob.
    public static let blockSize: Int = 8 * 1024 * 1024
    public static let maximumBlockCount = 50_000

    /// `blockSize`, or larger where the file would otherwise need more
    /// than `maximumBlockCount` blocks (8 MiB stops at about 390 GiB).
    public static func blockSize(forFileOf size: Int64) -> Int {
        max(blockSize, Int((size + Int64(maximumBlockCount) - 1) / Int64(maximumBlockCount)))
    }

    /// Max parallel block uploads inside a single Put Block List
    /// multipart. Bumps throughput on fast connections without
    /// monopolising the user's bandwidth.
    public static let maxBlockParallelism: Int = 4

    public init(
        credentialsCache: AzureCredentialsCache,
        session: URLSession = .shared,
        limiter: BandwidthLimiter? = nil
    ) {
        self.credentialsCache = credentialsCache
        self.session = session
        self.limiter = limiter
    }

    // MARK: - Upload

    /// Upload `localURL` to the supplied blob coordinates. Routes between
    /// single-shot and multipart based on file size. `progress` receives
    /// `(bytesTransferred, totalBytes)` snapshots. With a `precondition`
    /// the write (Put Blob or Put Block List) only succeeds while it
    /// holds; otherwise it throws `.preconditionFailed`. Returns the
    /// ETag the write answered with (unquoted).
    @discardableResult
    public func upload(
        account: S3Account,
        container: String,
        blob: String,
        localURL: URL,
        contentType: String?,
        precondition: WritePrecondition? = nil,
        progress: @Sendable @escaping (Int64, Int64) async -> Void
    ) async throws -> String? {
        // An unknown size must not be treated as 0: the single-shot
        // path would PUT an empty blob for a non-empty file.
        guard let size = try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw BucketeerError.sandboxAccessDenied(localURL)
        }
        let fileSize = Int64(size)

        let signer = try await credentialsCache.signer(for: account)
        let builder = AzureRequestBuilder(account: account)

        if fileSize < Self.multipartThreshold {
            let etag = try await singleShotUpload(
                builder: builder,
                signer: signer,
                container: container,
                blob: blob,
                localURL: localURL,
                fileSize: fileSize,
                contentType: contentType,
                precondition: precondition
            )
            await progress(fileSize, fileSize)
            return etag
        } else {
            return try await multipartUpload(
                builder: builder,
                signer: signer,
                container: container,
                blob: blob,
                localURL: localURL,
                fileSize: fileSize,
                contentType: contentType,
                precondition: precondition,
                progress: progress
            )
        }
    }

    private func singleShotUpload(
        builder: AzureRequestBuilder,
        signer: AzureSharedKeySigner,
        container: String,
        blob: String,
        localURL: URL,
        fileSize: Int64,
        contentType: String?,
        precondition: WritePrecondition?
    ) async throws -> String? {
        let data: Data
        do {
            data = try Data(contentsOf: localURL, options: .mappedIfSafe)
        } catch {
            throw BucketeerError.sandboxAccessDenied(localURL)
        }

        var request = URLRequest(url: builder.blobURL(container: container, blob: blob))
        request.httpMethod = "PUT"
        request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
        request.setValue(String(fileSize), forHTTPHeaderField: "Content-Length")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        Self.apply(precondition, to: &request)
        request.httpBody = data
        signer.sign(&request)

        let (responseData, response) = try await session.azureData(for: request)
        // Phase 13.2 — post-charge the limiter once the bytes have hit
        // the wire so the next call back-pressures correctly.
        await limiter?.consume(bytes: data.count)
        guard let http = response as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure PUT returned a non-HTTP response.")
        }
        try Self.check(http, body: responseData, container: container, blob: blob, precondition: precondition)
        return Self.etag(of: http)
    }

    private func multipartUpload(
        builder: AzureRequestBuilder,
        signer: AzureSharedKeySigner,
        container: String,
        blob: String,
        localURL: URL,
        fileSize: Int64,
        contentType: String?,
        precondition: WritePrecondition?,
        progress: @Sendable @escaping (Int64, Int64) async -> Void
    ) async throws -> String? {
        let blockSize = Int64(Self.blockSize(forFileOf: fileSize))
        let blockCount = Int((fileSize + blockSize - 1) / blockSize)
        let uploadSession = UUID()
        let blockIDs: [String] = (0..<blockCount).map {
            AzureRequestBuilder.blockID(session: uploadSession, index: $0)
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: localURL)
        } catch {
            throw BucketeerError.sandboxAccessDenied(localURL)
        }
        defer { try? handle.close() }

        // Counter for cumulative progress across parallel block uploads.
        // Lives inside an actor so the @Sendable progress closure has a
        // safe place to write.
        let counter = UploadProgressCounter(total: fileSize, callback: progress)

        try await withThrowingTaskGroup(of: Void.self) { group in
            var nextIndex = 0
            let inflightLimit = Self.maxBlockParallelism

            func enqueueBlock(at index: Int) throws {
                let offset = Int64(index) * blockSize
                let chunkSize = min(blockSize, fileSize - offset)
                try handle.seek(toOffset: UInt64(offset))
                // A short read would commit a block list that references
                // a block that was never staged.
                guard let chunk = try handle.read(upToCount: Int(chunkSize)),
                      chunk.count == Int(chunkSize)
                else {
                    throw BucketeerError.sandboxAccessDenied(localURL)
                }
                let blockID = blockIDs[index]

                group.addTask { [session, limiter] in
                    try await Self.putBlock(
                        builder: builder,
                        signer: signer,
                        session: session,
                        container: container,
                        blob: blob,
                        blockID: blockID,
                        data: chunk
                    )
                    // Phase 13.2 — charge the bandwidth bucket per
                    // committed block. Concurrent block tasks all
                    // serialise on the actor so the global throughput
                    // never exceeds the configured cap.
                    await limiter?.consume(bytes: chunk.count)
                    await counter.add(Int64(chunk.count))
                }
            }

            for _ in 0..<min(inflightLimit, blockCount) {
                try enqueueBlock(at: nextIndex)
                nextIndex += 1
            }
            while nextIndex < blockCount {
                try await group.next()
                try enqueueBlock(at: nextIndex)
                nextIndex += 1
            }
            // Drain remaining tasks.
            try await group.waitForAll()
        }

        let etag = try await commitBlockList(
            builder: builder,
            signer: signer,
            container: container,
            blob: blob,
            blockIDs: blockIDs,
            contentType: contentType,
            precondition: precondition
        )
        await progress(fileSize, fileSize)
        return etag
    }

    private static func putBlock(
        builder: AzureRequestBuilder,
        signer: AzureSharedKeySigner,
        session: URLSession,
        container: String,
        blob: String,
        blockID: String,
        data: Data
    ) async throws {
        var request = URLRequest(
            url: builder.putBlockURL(container: container, blob: blob, blockID: blockID)
        )
        request.httpMethod = "PUT"
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        request.httpBody = data
        signer.sign(&request)

        let (responseData, response) = try await session.azureData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure Put Block returned a non-HTTP response.")
        }
        if let mapped = AzureBlobObjectStore.mapHTTP(
            http, body: responseData, bucket: container, key: blob
        ) {
            throw mapped
        }
    }

    private func commitBlockList(
        builder: AzureRequestBuilder,
        signer: AzureSharedKeySigner,
        container: String,
        blob: String,
        blockIDs: [String],
        contentType: String?,
        precondition: WritePrecondition?
    ) async throws -> String? {
        let body = AzureRequestBuilder.blockListXML(blockIDs: blockIDs)
        var request = URLRequest(
            url: builder.putBlockListURL(container: container, blob: blob)
        )
        request.httpMethod = "PUT"
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "x-ms-blob-content-type")
        }
        // Staged blocks are invisible until this commit, so the
        // precondition belongs here.
        Self.apply(precondition, to: &request)
        request.httpBody = body
        signer.sign(&request)

        let (responseData, response) = try await session.azureData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure Put Block List returned a non-HTTP response.")
        }
        try Self.check(http, body: responseData, container: container, blob: blob, precondition: precondition)
        return Self.etag(of: http)
    }

    // MARK: - Preconditions

    private static func apply(_ precondition: WritePrecondition?, to request: inout URLRequest) {
        switch precondition {
        case .ifMatch(let etag):
            request.setValue(ETag.quoted(etag), forHTTPHeaderField: "If-Match")
        case .ifAbsent:
            request.setValue("*", forHTTPHeaderField: "If-None-Match")
        case nil:
            break
        }
    }

    /// A create-only write that finds the blob already there answers
    /// 409 (BlobAlreadyExists) rather than 412; both mean the
    /// precondition failed.
    private static func check(
        _ http: HTTPURLResponse,
        body: Data?,
        container: String,
        blob: String,
        precondition: WritePrecondition?
    ) throws {
        if precondition == .ifAbsent, http.statusCode == 409 || http.statusCode == 412 {
            throw BucketeerError.preconditionFailed(key: blob)
        }
        if let mapped = AzureBlobObjectStore.mapHTTP(http, body: body, bucket: container, key: blob) {
            throw mapped
        }
    }

    private static func etag(of http: HTTPURLResponse) -> String? {
        http.value(forHTTPHeaderField: "ETag").map(ETag.normalized)
    }

    // MARK: - Download

    /// Download the blob to `localURL`. Routes between single-GET and
    /// ranged parallel-GET based on the head-reported size. Zero-byte
    /// blobs short-circuit to an empty local file. Every GET is pinned
    /// to the version the HEAD reported; with `ifMatch` that version
    /// must be `ifMatch`, otherwise `.preconditionFailed` is thrown.
    public func download(
        account: S3Account,
        container: String,
        blob: String,
        localURL: URL,
        ifMatch expectedVersion: String? = nil,
        progress: @Sendable @escaping (Int64, Int64) async -> Void
    ) async throws {
        let signer = try await credentialsCache.signer(for: account)
        let builder = AzureRequestBuilder(account: account)

        // HEAD to learn the size; same pattern as the S3 path.
        var headRequest = URLRequest(
            url: builder.blobPropertiesURL(container: container, blob: blob)
        )
        headRequest.httpMethod = "HEAD"
        signer.sign(&headRequest)
        let (_, headResponse) = try await session.azureData(for: headRequest)
        guard let headHTTP = headResponse as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure HEAD returned a non-HTTP response.")
        }
        if let mapped = AzureBlobObjectStore.mapHTTP(
            headHTTP, body: nil, bucket: container, key: blob
        ) {
            throw mapped
        }
        let total = headHTTP.value(forHTTPHeaderField: "Content-Length")
            .flatMap { Int64($0) } ?? 0
        let version = headHTTP.value(forHTTPHeaderField: "ETag")
        if let expectedVersion, !ETag.matches(base: expectedVersion, current: version) {
            throw BucketeerError.preconditionFailed(key: blob)
        }

        // The existing file is replaced only by a complete download.
        try await StagedDownload.write(to: localURL) { staging in
            if total == 0 {
                try Data().write(to: staging)
                await progress(0, 0)
                return
            }

            await progress(0, total)

            if total < Self.multipartThreshold {
                try await singleShotDownload(
                    builder: builder,
                    signer: signer,
                    container: container,
                    blob: blob,
                    version: version,
                    localURL: staging,
                    total: total,
                    progress: progress
                )
            } else {
                try await rangedDownload(
                    builder: builder,
                    signer: signer,
                    container: container,
                    blob: blob,
                    version: version,
                    localURL: staging,
                    total: total,
                    progress: progress
                )
            }
        }
    }

    private func singleShotDownload(
        builder: AzureRequestBuilder,
        signer: AzureSharedKeySigner,
        container: String,
        blob: String,
        version: String?,
        localURL: URL,
        total: Int64,
        progress: @Sendable @escaping (Int64, Int64) async -> Void
    ) async throws {
        var request = URLRequest(url: builder.blobDownloadURL(container: container, blob: blob))
        request.httpMethod = "GET"
        if let version {
            request.setValue(version, forHTTPHeaderField: "If-Match")
        }
        signer.sign(&request)

        let (data, response) = try await session.azureData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure GET returned a non-HTTP response.")
        }
        if let mapped = AzureBlobObjectStore.mapHTTP(
            http, body: data, bucket: container, key: blob
        ) {
            throw mapped
        }
        // Phase 13.2 — post-charge after the bytes have arrived.
        await limiter?.consume(bytes: data.count)
        try data.write(to: localURL)
        await progress(total, total)
    }

    /// `version` is the ETag the HEAD reported. Every range is
    /// conditional on it, so a blob replaced mid-download fails the
    /// transfer instead of mixing bytes of two versions.
    private func rangedDownload(
        builder: AzureRequestBuilder,
        signer: AzureSharedKeySigner,
        container: String,
        blob: String,
        version: String?,
        localURL: URL,
        total: Int64,
        progress: @Sendable @escaping (Int64, Int64) async -> Void
    ) async throws {
        // Pre-allocate the destination so multiple writers can seek
        // independently. Writing happens in chunks under an actor so
        // FileHandle stays single-threaded.
        FileManager.default.createFile(atPath: localURL.path, contents: nil)
        let writeHandle: FileHandle
        do {
            writeHandle = try FileHandle(forWritingTo: localURL)
        } catch {
            throw BucketeerError.sandboxAccessDenied(localURL)
        }
        try writeHandle.truncate(atOffset: UInt64(total))
        let writer = DownloadWriter(handle: writeHandle, total: total, callback: progress)

        let chunkSize = Int64(Self.blockSize)
        let chunkCount = Int((total + chunkSize - 1) / chunkSize)

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                var nextIndex = 0
                func enqueueRange(_ index: Int) {
                    let offset = Int64(index) * chunkSize
                    let length = min(chunkSize, total - offset)
                    group.addTask { [session, limiter] in
                        try await Self.fetchRange(
                            builder: builder,
                            signer: signer,
                            session: session,
                            container: container,
                            blob: blob,
                            version: version,
                            offset: offset,
                            length: length,
                            writer: writer
                        )
                        // Phase 13.2 — charge the bucket once the
                        // ranged GET has landed its bytes.
                        await limiter?.consume(bytes: Int(length))
                    }
                }
                for _ in 0..<min(Self.maxBlockParallelism, chunkCount) {
                    enqueueRange(nextIndex)
                    nextIndex += 1
                }
                while nextIndex < chunkCount {
                    try await group.next()
                    enqueueRange(nextIndex)
                    nextIndex += 1
                }
                try await group.waitForAll()
            }
        } catch {
            await writer.close()
            throw error
        }
        await writer.close()
    }

    private static func fetchRange(
        builder: AzureRequestBuilder,
        signer: AzureSharedKeySigner,
        session: URLSession,
        container: String,
        blob: String,
        version: String?,
        offset: Int64,
        length: Int64,
        writer: DownloadWriter
    ) async throws {
        var request = URLRequest(url: builder.blobDownloadURL(container: container, blob: blob))
        request.httpMethod = "GET"
        let endInclusive = offset + length - 1
        request.setValue("bytes=\(offset)-\(endInclusive)", forHTTPHeaderField: "Range")
        if let version {
            request.setValue(version, forHTTPHeaderField: "If-Match")
        }
        signer.sign(&request)

        let (data, response) = try await session.azureData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure ranged GET returned a non-HTTP response.")
        }
        if let mapped = AzureBlobObjectStore.mapHTTP(
            http, body: data, bucket: container, key: blob
        ) {
            throw mapped
        }
        // A proxy or misbehaving server that ignores
        // the Range header returns 200 with the full body — writing
        // that into our chunk slot would scramble the file. Demand
        // 206 (Partial Content) and verify the response is exactly
        // the bytes we asked for. The single-shot path is the right
        // place for whole-body downloads.
        guard http.statusCode == 206 else {
            throw BucketeerError.providerError(
                statusCode: http.statusCode,
                message: "Azure ignored the Range header and returned the full blob; ranged download aborted."
            )
        }
        guard Int64(data.count) == length else {
            throw BucketeerError.providerError(
                statusCode: http.statusCode,
                message: "Azure ranged GET returned \(data.count) bytes; expected \(length)."
            )
        }
        // Write failures now propagate so a disk-full
        // or permission error fails the task group instead of leaving
        // a corrupt partial file marked complete.
        try await writer.write(data, at: offset)
    }
}

// MARK: - Helpers

/// Aggregates per-block upload byte counts and bridges them out through
/// the @Sendable progress callback.
private actor UploadProgressCounter {
    private let total: Int64
    private var bytesSoFar: Int64 = 0
    private let callback: @Sendable (Int64, Int64) async -> Void

    public init(total: Int64, callback: @escaping @Sendable (Int64, Int64) async -> Void) {
        self.total = total
        self.callback = callback
    }

    public func add(_ bytes: Int64) async {
        bytesSoFar += bytes
        await callback(bytesSoFar, total)
    }
}

/// Coordinates writes from multiple ranged-GET tasks into the same
/// `FileHandle`. Each write does an explicit seek + write to its assigned
/// offset; `FileManager` does not give us a thread-safe positional write.
private actor DownloadWriter {
    private var handle: FileHandle?
    private let total: Int64
    private var bytesSoFar: Int64 = 0
    private let callback: @Sendable (Int64, Int64) async -> Void

    public init(handle: FileHandle, total: Int64, callback: @escaping @Sendable (Int64, Int64) async -> Void) {
        self.handle = handle
        self.total = total
        self.callback = callback
    }

    /// Write failures now propagate to the caller so a
    /// disk-full, permission, or invalid-handle error fails the outer
    /// throwing task group immediately instead of leaving a corrupt
    /// partial file marked complete.
    public func write(_ data: Data, at offset: Int64) async throws {
        guard let handle else {
            throw BucketeerError.unknown(message: "Download writer was closed before all chunks landed.")
        }
        do {
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: data)
        } catch {
            throw BucketeerError.sandboxAccessDenied(URL(fileURLWithPath: "(download writer)"))
        }
        bytesSoFar += Int64(data.count)
        await callback(bytesSoFar, total)
    }

    public func close() async {
        try? handle?.close()
        handle = nil
    }
}
