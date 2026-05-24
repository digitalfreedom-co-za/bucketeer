//
//  MultipartUploadRecord.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import SwiftData

/// SwiftData persistence for `MultipartUploadCheckpoint`. Phase 13.10.
/// Lives in a dedicated host-only container — see
/// `AppContainer.makeCheckpointContainer`. Completed-parts list is
/// serialised as a JSON blob so the schema doesn't have to spawn a
/// per-part row for what is conceptually one upload.
@Model
public final class MultipartUploadRecord {
    @Attribute(.unique) public var id: UUID
    public var accountID: UUID
    public var bucket: String
    public var key: String
    public var localPath: String
    public var fileSize: Int64
    public var partSize: Int
    public var uploadId: String
    public var createdAt: Date
    public var lastTouchedAt: Date
    public var completedPartsData: Data

    public init(checkpoint: MultipartUploadCheckpoint) {
        self.id = checkpoint.id
        self.accountID = checkpoint.accountID
        self.bucket = checkpoint.bucket
        self.key = checkpoint.key
        self.localPath = checkpoint.localPath
        self.fileSize = checkpoint.fileSize
        self.partSize = checkpoint.partSize
        self.uploadId = checkpoint.uploadId
        self.createdAt = checkpoint.createdAt
        self.lastTouchedAt = checkpoint.lastTouchedAt
        let encoder = JSONEncoder()
        self.completedPartsData = (try? encoder.encode(checkpoint.completedParts)) ?? Data()
    }

    public func update(from checkpoint: MultipartUploadCheckpoint) {
        self.lastTouchedAt = checkpoint.lastTouchedAt
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(checkpoint.completedParts) {
            self.completedPartsData = data
        }
    }

    public var snapshot: MultipartUploadCheckpoint? {
        let decoder = JSONDecoder()
        let parts = (try? decoder.decode([CompletedUploadPart].self, from: completedPartsData)) ?? []
        return MultipartUploadCheckpoint(
            id: id,
            accountID: accountID,
            bucket: bucket,
            key: key,
            localPath: localPath,
            fileSize: fileSize,
            partSize: partSize,
            uploadId: uploadId,
            createdAt: createdAt,
            lastTouchedAt: lastTouchedAt,
            completedParts: parts.sorted { $0.partNumber < $1.partNumber }
        )
    }
}
