//
//  CheckpointStore.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import SwiftData

/// SwiftData-backed `CheckpointStoring` implementation. Phase 13.10.
///
/// Checkpoints are addressed by `id` for upsert / delete, and by the
/// `(accountID, bucket, key, localPath, fileSize)` tuple for `find` —
/// that combination uniquely identifies "this upload of this file to
/// this destination", so re-queueing the same local file resumes the
/// same in-flight upload.
@ModelActor
public actor CheckpointStore: CheckpointStoring {

    public func find(
        accountID: UUID,
        bucket: String,
        key: String,
        localPath: String,
        fileSize: Int64
    ) async throws -> MultipartUploadCheckpoint? {
        do {
            let descriptor = FetchDescriptor<MultipartUploadRecord>(
                predicate: #Predicate {
                    $0.accountID == accountID
                        && $0.bucket == bucket
                        && $0.key == key
                        && $0.localPath == localPath
                        && $0.fileSize == fileSize
                }
            )
            return try modelContext.fetch(descriptor).first?.snapshot
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }

    public func upsert(_ checkpoint: MultipartUploadCheckpoint) async throws {
        do {
            let id = checkpoint.id
            let descriptor = FetchDescriptor<MultipartUploadRecord>(
                predicate: #Predicate { $0.id == id }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                existing.update(from: checkpoint)
            } else {
                modelContext.insert(MultipartUploadRecord(checkpoint: checkpoint))
            }
            try modelContext.save()
        } catch let error as BucketeerError {
            throw error
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }

    public func delete(id: UUID) async throws {
        do {
            let descriptor = FetchDescriptor<MultipartUploadRecord>(
                predicate: #Predicate { $0.id == id }
            )
            if let record = try modelContext.fetch(descriptor).first {
                modelContext.delete(record)
                try modelContext.save()
            }
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }

    public func all() async throws -> [MultipartUploadCheckpoint] {
        do {
            let descriptor = FetchDescriptor<MultipartUploadRecord>(
                sortBy: [SortDescriptor(\.lastTouchedAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor).compactMap(\.snapshot)
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }
}
