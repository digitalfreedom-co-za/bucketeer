//
//  S3ResumableUploader.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
@preconcurrency import SotoS3
@preconcurrency import NIOCore

/// Resumable multipart-upload driver for the S3 family. Phase 13.10.
///
/// Replaces Soto's built-in `multipartUpload` for files large enough
/// (default ≥ 50 MB) that an interruption costs noticeable bandwidth
/// to redo from scratch. After every part lands successfully, the
/// driver persists the upload ID + the list of completed (part
/// number, ETag) pairs through a `CheckpointStoring` actor. If the
/// app dies mid-upload, the next call with the same `(account,
/// bucket, key, localPath, fileSize)` tuple loads the checkpoint,
/// reconciles with the server via `listParts`, and resumes from the
/// next pending part.
///
/// v1 ships the simplest correct variant — sequential parts. The
/// throughput hit vs. Soto's parallel helper is acceptable for the
/// ≥ 50 MB band where the wire RTT is dwarfed by the chunk size; the
/// resume guarantee outweighs the cost. A future phase will fan out
/// `uploadPart` calls under a semaphore.
public struct S3ResumableUploader: Sendable {
    /// Files below this size fall back to Soto's helper.
    public static let resumableThreshold: Int64 = 50 * 1024 * 1024
    /// Part size for the manual loop — matches Soto's default so the
    /// hand-rolled path uses the same number of parts.
    public static let partSize: Int = 8 * 1024 * 1024

    public let factory: S3ClientFactory
    public let checkpointStore: any CheckpointStoring

    public init(factory: S3ClientFactory, checkpointStore: any CheckpointStoring) {
        self.factory = factory
        self.checkpointStore = checkpointStore
    }

    /// Upload `localURL` to `bucket/key`. Returns once the
    /// `completeMultipartUpload` succeeds. `progress` is called with
    /// the cumulative number of confirmed bytes after every part —
    /// good enough for the `TransferManager` to keep the progress
    /// bar moving without per-byte updates.
    public func upload(
        account: S3Account,
        bucket: String,
        key: String,
        localURL: URL,
        contentType: String?,
        fileSize: Int64,
        progress: @Sendable @escaping (Int64) async -> Void
    ) async throws {
        // Service-layer contract: raw Soto errors from the multipart
        // calls (createMultipartUpload, listParts, uploadPart,
        // completeMultipartUpload) must not escape — translate them
        // through the same mapper S3Service uses. Cancellation and
        // already-mapped errors pass through untouched.
        do {
            try await performUpload(
                account: account,
                bucket: bucket,
                key: key,
                localURL: localURL,
                contentType: contentType,
                fileSize: fileSize,
                progress: progress
            )
        } catch let error as BucketeerError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw S3Service.map(error, bucket: bucket, key: key)
        }
    }

    private func performUpload(
        account: S3Account,
        bucket: String,
        key: String,
        localURL: URL,
        contentType: String?,
        fileSize: Int64,
        progress: @Sendable @escaping (Int64) async -> Void
    ) async throws {
        let s3 = try await factory.client(for: account)
        // 1. Find or create a checkpoint.
        var checkpoint = try await loadOrCreateCheckpoint(
            account: account,
            bucket: bucket,
            key: key,
            localURL: localURL,
            fileSize: fileSize,
            contentType: contentType,
            s3: s3
        )

        // 2. Reconcile with the server. Parts that the server already
        // confirms get adopted into the checkpoint so we don't re-
        // upload them.
        let serverParts = try await listServerParts(
            s3: s3,
            bucket: bucket,
            key: key,
            uploadId: checkpoint.uploadId
        )
        let serverPartNumbers = Set(serverParts.map(\.partNumber))
        let localPartNumbers = Set(checkpoint.completedParts.map(\.partNumber))
        if serverPartNumbers != localPartNumbers {
            // Adopt the server's view of truth — the local list might
            // have been incomplete after a crash between "uploadPart
            // returned" and "checkpoint saved".
            checkpoint.completedParts = serverParts.sorted { $0.partNumber < $1.partNumber }
            checkpoint.lastTouchedAt = Date()
            try await checkpointStore.upsert(checkpoint)
        }

        // 3. Upload remaining parts sequentially.
        // A zero-byte file yields totalParts == 0 and `1...0` traps.
        // Callers route small files through single-shot PutObject, but
        // this is a public API — reject instead of crashing.
        let totalParts = Int((fileSize + Int64(checkpoint.partSize) - 1) / Int64(checkpoint.partSize))
        guard totalParts >= 1 else {
            _ = try? await s3.abortMultipartUpload(.init(
                bucket: bucket,
                key: key,
                uploadId: checkpoint.uploadId
            ))
            try? await checkpointStore.delete(id: checkpoint.id)
            throw BucketeerError.unknown(
                message: "Multipart upload requires a non-empty file."
            )
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: localURL)
        } catch {
            throw BucketeerError.sandboxAccessDenied(localURL)
        }
        defer { try? handle.close() }

        let completedSoFar: Int64 = checkpoint.completedParts.reduce(0) { acc, _ in
            // We don't know each part's actual byte size exactly
            // (last part is smaller). For progress purposes, treat
            // every confirmed part as a full part — the underflow on
            // the very last one is negligible visually.
            acc + Int64(checkpoint.partSize)
        }
        var transferred = min(completedSoFar, fileSize)
        await progress(transferred)

        for partNumber in 1...totalParts {
            try Task.checkCancellation()
            if checkpoint.completedParts.contains(where: { $0.partNumber == partNumber }) {
                continue
            }
            let offset = Int64(partNumber - 1) * Int64(checkpoint.partSize)
            try handle.seek(toOffset: UInt64(offset))
            let remaining = fileSize - offset
            let chunkSize = Int(min(Int64(checkpoint.partSize), remaining))
            guard let chunk = try handle.read(upToCount: chunkSize) else {
                throw BucketeerError.unknown(
                    message: "Read returned no data at offset \(offset)."
                )
            }
            let etag = try await uploadPart(
                s3: s3,
                bucket: bucket,
                key: key,
                uploadId: checkpoint.uploadId,
                partNumber: partNumber,
                data: chunk
            )
            checkpoint.completedParts.append(
                CompletedUploadPart(partNumber: partNumber, etag: etag)
            )
            checkpoint.lastTouchedAt = Date()
            try await checkpointStore.upsert(checkpoint)
            transferred = min(transferred + Int64(chunk.count), fileSize)
            await progress(transferred)
        }

        // 4. Complete + drop the checkpoint.
        try await completeMultipart(
            s3: s3,
            bucket: bucket,
            key: key,
            uploadId: checkpoint.uploadId,
            parts: checkpoint.completedParts
        )
        try? await checkpointStore.delete(id: checkpoint.id)
        await progress(fileSize)
    }

    // MARK: - Private

    private func loadOrCreateCheckpoint(
        account: S3Account,
        bucket: String,
        key: String,
        localURL: URL,
        fileSize: Int64,
        contentType: String?,
        s3: S3
    ) async throws -> MultipartUploadCheckpoint {
        let fingerprint = MultipartUploadCheckpoint.fingerprint(for: localURL)
        if let existing = try await checkpointStore.find(
            accountID: account.id,
            bucket: bucket,
            key: key,
            localPath: localURL.path,
            fileSize: fileSize
        ) {
            // Codex audit fix (high #3): a stale checkpoint with the
            // same path + size but a different mtime is a *different
            // file*. Reusing its uploadId would assemble the final
            // object from a mix of old and new parts. Drop and
            // restart.
            if existing.fileFingerprint == fingerprint {
                return existing
            }
            // Codex R3 (medium): also abort the dangling multipart
            // upload on the server so the orphan parts aren't
            // billed until the bucket's lifecycle policy reaps
            // them. Best-effort — a failure here doesn't block
            // creating the fresh upload.
            _ = try? await s3.abortMultipartUpload(.init(
                bucket: bucket,
                key: key,
                uploadId: existing.uploadId
            ))
            try? await checkpointStore.delete(id: existing.id)
        }
        let response = try await s3.createMultipartUpload(.init(
            bucket: bucket,
            contentType: contentType,
            key: key
        ))
        guard let uploadId = response.uploadId else {
            throw BucketeerError.providerError(
                statusCode: 0,
                message: "createMultipartUpload returned no uploadId."
            )
        }
        let checkpoint = MultipartUploadCheckpoint(
            accountID: account.id,
            bucket: bucket,
            key: key,
            localPath: localURL.path,
            fileSize: fileSize,
            partSize: Self.partSize,
            uploadId: uploadId,
            fileFingerprint: fingerprint
        )
        try await checkpointStore.upsert(checkpoint)
        return checkpoint
    }

    private func listServerParts(
        s3: S3,
        bucket: String,
        key: String,
        uploadId: String
    ) async throws -> [CompletedUploadPart] {
        var parts: [CompletedUploadPart] = []
        var marker: Int? = nil
        repeat {
            let response = try await s3.listParts(.init(
                bucket: bucket,
                key: key,
                partNumberMarker: marker.map(String.init),
                uploadId: uploadId
            ))
            for entry in response.parts ?? [] {
                guard let pn = entry.partNumber, let tag = entry.eTag else { continue }
                parts.append(
                    CompletedUploadPart(partNumber: pn, etag: tag)
                )
            }
            if response.isTruncated == true,
               let next = response.nextPartNumberMarker {
                marker = Int(next)
            } else {
                marker = nil
            }
        } while marker != nil
        return parts
    }

    private func uploadPart(
        s3: S3,
        bucket: String,
        key: String,
        uploadId: String,
        partNumber: Int,
        data: Data
    ) async throws -> String {
        let buffer = ByteBuffer(bytes: data)
        let response = try await s3.uploadPart(.init(
            body: AWSHTTPBody(buffer: buffer),
            bucket: bucket,
            key: key,
            partNumber: partNumber,
            uploadId: uploadId
        ))
        guard let etag = response.eTag else {
            throw BucketeerError.providerError(
                statusCode: 0,
                message: "uploadPart \(partNumber) returned no ETag."
            )
        }
        return etag
    }

    private func completeMultipart(
        s3: S3,
        bucket: String,
        key: String,
        uploadId: String,
        parts: [CompletedUploadPart]
    ) async throws {
        let sorted = parts.sorted { $0.partNumber < $1.partNumber }
        let completed = S3.CompletedMultipartUpload(
            parts: sorted.map {
                S3.CompletedPart(eTag: $0.etag, partNumber: $0.partNumber)
            }
        )
        _ = try await s3.completeMultipartUpload(.init(
            bucket: bucket,
            key: key,
            multipartUpload: completed,
            uploadId: uploadId
        ))
    }
}
