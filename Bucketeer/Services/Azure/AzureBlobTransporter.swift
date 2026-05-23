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
struct AzureBlobTransporter: Sendable {
    let credentialsCache: AzureCredentialsCache
    let session: URLSession

    /// Switch threshold between single-shot Put Block Blob and the
    /// staged Put Block + Put Block List path. Mirrors the S3 multipart
    /// threshold so users see consistent behaviour across providers.
    static let multipartThreshold: Int64 = 5 * 1024 * 1024

    /// Size of each staged block. Azure allows up to 4000 MiB per block
    /// in the most recent API; 8 MiB matches the S3 part size for
    /// symmetry and is well within the 50 000 block-per-blob limit
    /// (50 000 × 8 MiB ≈ 400 GiB, comfortable for v1).
    static let blockSize: Int = 8 * 1024 * 1024

    /// Max parallel block uploads inside a single Put Block List
    /// multipart. Bumps throughput on fast connections without
    /// monopolising the user's bandwidth.
    static let maxBlockParallelism: Int = 4

    init(credentialsCache: AzureCredentialsCache, session: URLSession = .shared) {
        self.credentialsCache = credentialsCache
        self.session = session
    }

    // MARK: - Upload

    /// Upload `localURL` to the supplied blob coordinates. Routes between
    /// single-shot and multipart based on file size. `progress` receives
    /// `(bytesTransferred, totalBytes)` snapshots.
    func upload(
        account: S3Account,
        container: String,
        blob: String,
        localURL: URL,
        contentType: String?,
        progress: @Sendable @escaping (Int64, Int64) async -> Void
    ) async throws {
        let size = (try? localURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        let fileSize = Int64(size ?? 0)

        let signer = try await credentialsCache.signer(for: account)
        let builder = AzureRequestBuilder(account: account)

        if fileSize < Self.multipartThreshold {
            try await singleShotUpload(
                builder: builder,
                signer: signer,
                container: container,
                blob: blob,
                localURL: localURL,
                fileSize: fileSize,
                contentType: contentType
            )
            await progress(fileSize, fileSize)
        } else {
            try await multipartUpload(
                builder: builder,
                signer: signer,
                container: container,
                blob: blob,
                localURL: localURL,
                fileSize: fileSize,
                contentType: contentType,
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
        contentType: String?
    ) async throws {
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
        request.httpBody = data
        signer.sign(&request)

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure PUT returned a non-HTTP response.")
        }
        if let mapped = AzureBlobObjectStore.mapHTTP(
            http, body: responseData, bucket: container, key: blob
        ) {
            throw mapped
        }
    }

    private func multipartUpload(
        builder: AzureRequestBuilder,
        signer: AzureSharedKeySigner,
        container: String,
        blob: String,
        localURL: URL,
        fileSize: Int64,
        contentType: String?,
        progress: @Sendable @escaping (Int64, Int64) async -> Void
    ) async throws {
        let blockSize = Int64(Self.blockSize)
        let blockCount = Int((fileSize + blockSize - 1) / blockSize)
        let blockIDs: [String] = (0..<blockCount).map { AzureRequestBuilder.blockID(index: $0) }

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
                guard let chunk = try handle.read(upToCount: Int(chunkSize)) else { return }
                let blockID = blockIDs[index]

                group.addTask { [session] in
                    try await Self.putBlock(
                        builder: builder,
                        signer: signer,
                        session: session,
                        container: container,
                        blob: blob,
                        blockID: blockID,
                        data: chunk
                    )
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

        try await commitBlockList(
            builder: builder,
            signer: signer,
            container: container,
            blob: blob,
            blockIDs: blockIDs,
            contentType: contentType
        )
        await progress(fileSize, fileSize)
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

        let (responseData, response) = try await session.data(for: request)
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
        contentType: String?
    ) async throws {
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
        request.httpBody = body
        signer.sign(&request)

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure Put Block List returned a non-HTTP response.")
        }
        if let mapped = AzureBlobObjectStore.mapHTTP(
            http, body: responseData, bucket: container, key: blob
        ) {
            throw mapped
        }
    }

    // MARK: - Download

    /// Download the blob to `localURL`. Routes between single-GET and
    /// ranged parallel-GET based on the head-reported size. Zero-byte
    /// blobs short-circuit to an empty local file.
    func download(
        account: S3Account,
        container: String,
        blob: String,
        localURL: URL,
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
        let (_, headResponse) = try await session.data(for: headRequest)
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

        // Truncate / remove existing.
        try? FileManager.default.removeItem(at: localURL)

        if total == 0 {
            FileManager.default.createFile(atPath: localURL.path, contents: nil)
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
                localURL: localURL,
                total: total,
                progress: progress
            )
        } else {
            try await rangedDownload(
                builder: builder,
                signer: signer,
                container: container,
                blob: blob,
                localURL: localURL,
                total: total,
                progress: progress
            )
        }
    }

    private func singleShotDownload(
        builder: AzureRequestBuilder,
        signer: AzureSharedKeySigner,
        container: String,
        blob: String,
        localURL: URL,
        total: Int64,
        progress: @Sendable @escaping (Int64, Int64) async -> Void
    ) async throws {
        var request = URLRequest(url: builder.blobDownloadURL(container: container, blob: blob))
        request.httpMethod = "GET"
        signer.sign(&request)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure GET returned a non-HTTP response.")
        }
        if let mapped = AzureBlobObjectStore.mapHTTP(
            http, body: data, bucket: container, key: blob
        ) {
            throw mapped
        }
        try data.write(to: localURL)
        await progress(total, total)
    }

    private func rangedDownload(
        builder: AzureRequestBuilder,
        signer: AzureSharedKeySigner,
        container: String,
        blob: String,
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
                    group.addTask { [session] in
                        try await Self.fetchRange(
                            builder: builder,
                            signer: signer,
                            session: session,
                            container: container,
                            blob: blob,
                            offset: offset,
                            length: length,
                            writer: writer
                        )
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
        offset: Int64,
        length: Int64,
        writer: DownloadWriter
    ) async throws {
        var request = URLRequest(url: builder.blobDownloadURL(container: container, blob: blob))
        request.httpMethod = "GET"
        let endInclusive = offset + length - 1
        request.setValue("bytes=\(offset)-\(endInclusive)", forHTTPHeaderField: "Range")
        signer.sign(&request)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BucketeerError.unknown(message: "Azure ranged GET returned a non-HTTP response.")
        }
        // 200 (full body) and 206 (partial) both indicate success.
        if !(200..<300).contains(http.statusCode) {
            if let mapped = AzureBlobObjectStore.mapHTTP(
                http, body: data, bucket: container, key: blob
            ) {
                throw mapped
            }
        }
        await writer.write(data, at: offset)
    }
}

// MARK: - Helpers

/// Aggregates per-block upload byte counts and bridges them out through
/// the @Sendable progress callback.
private actor UploadProgressCounter {
    private let total: Int64
    private var bytesSoFar: Int64 = 0
    private let callback: @Sendable (Int64, Int64) async -> Void

    init(total: Int64, callback: @escaping @Sendable (Int64, Int64) async -> Void) {
        self.total = total
        self.callback = callback
    }

    func add(_ bytes: Int64) async {
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

    init(handle: FileHandle, total: Int64, callback: @escaping @Sendable (Int64, Int64) async -> Void) {
        self.handle = handle
        self.total = total
        self.callback = callback
    }

    func write(_ data: Data, at offset: Int64) async {
        guard let handle else { return }
        do {
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: data)
            bytesSoFar += Int64(data.count)
            await callback(bytesSoFar, total)
        } catch {
            // Swallowing here is intentional — the outer task group will
            // surface the failure of the *next* fetch (or the file gets
            // closed and a subsequent operation fails). Failing the write
            // silently is preferable to crashing the entire transfer on
            // a transient disk hiccup.
        }
    }

    func close() async {
        try? handle?.close()
        handle = nil
    }
}
