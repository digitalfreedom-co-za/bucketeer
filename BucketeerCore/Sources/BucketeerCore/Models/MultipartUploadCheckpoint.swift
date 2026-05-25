//
//  MultipartUploadCheckpoint.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation

/// One completed part inside a resumable multipart upload. Phase
/// 13.10. The S3 API needs both the part number and its returned
/// ETag to finalise the upload with `completeMultipartUpload`.
public struct CompletedUploadPart: Hashable, Sendable, Codable {
    public let partNumber: Int
    public let etag: String

    public init(partNumber: Int, etag: String) {
        self.partNumber = partNumber
        self.etag = etag
    }
}

/// Persistent state for one in-progress multipart upload. Phase 13.10.
/// Used by the resumable upload path so an upload that's interrupted
/// (network drop, app quit, Mac sleep, …) can be resumed on the next
/// launch without re-sending parts that already landed on the server.
public struct MultipartUploadCheckpoint: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let accountID: UUID
    public let bucket: String
    public let key: String
    public let localPath: String
    public let fileSize: Int64
    public let partSize: Int
    public let uploadId: String
    public let createdAt: Date
    public var lastTouchedAt: Date
    /// File-identity fingerprint at the moment the upload started —
    /// Codex audit fix (high #3). Without this, a different file
    /// with the same path + size as a stale checkpoint would have
    /// its first parts assembled from the *previous* file's
    /// already-uploaded chunks. Format is opaque to callers; see
    /// `MultipartUploadCheckpoint.fingerprint(for:)`.
    public let fileFingerprint: String
    /// Parts confirmed by the server. Sorted by part number on read so
    /// the resumable loop can compute the next part with a simple
    /// `completedParts.count + 1`.
    public var completedParts: [CompletedUploadPart]

    public init(
        id: UUID = UUID(),
        accountID: UUID,
        bucket: String,
        key: String,
        localPath: String,
        fileSize: Int64,
        partSize: Int,
        uploadId: String,
        createdAt: Date = Date(),
        lastTouchedAt: Date = Date(),
        fileFingerprint: String,
        completedParts: [CompletedUploadPart] = []
    ) {
        self.id = id
        self.accountID = accountID
        self.bucket = bucket
        self.key = key
        self.localPath = localPath
        self.fileSize = fileSize
        self.partSize = partSize
        self.uploadId = uploadId
        self.createdAt = createdAt
        self.lastTouchedAt = lastTouchedAt
        self.fileFingerprint = fileFingerprint
        self.completedParts = completedParts
    }

    /// Cheap identity blob for a local file — mtime + size. Mtime
    /// changes whenever the file's content does (sandbox writes
    /// always touch mtime), so two files with the same path + size
    /// but different content produce different fingerprints. We
    /// avoid hashing the whole file because resumable uploads
    /// specifically target the huge-file band where rehashing on
    /// every resume would dwarf the part-upload cost.
    public static func fingerprint(for url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        return "\(Int64(mtime))|\(size)"
    }
}
