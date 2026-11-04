//
//  SyncFingerprintStore.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import SwiftData

public protocol SyncFingerprintStoring: Sendable {
    /// Empty when the job has never recorded any.
    func fingerprints(jobID: UUID) async throws -> [String: LocalFileFingerprint]
    func replace(jobID: UUID, with fingerprints: [String: LocalFileFingerprint]) async throws
    /// Drops the rows of every job not in `jobIDs`.
    func removeAll(except jobIDs: Set<UUID>) async throws
}

/// SwiftData-backed `SyncFingerprintStoring`. Lives in its own store
/// file, so the schema shared with the File Provider extension stays
/// untouched; a job without a row falls back to comparing dates.
@ModelActor
public actor SyncFingerprintStore: SyncFingerprintStoring {

    public static let schema = Schema([SyncFingerprintRecord.self])

    public static func makeContainer(url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration("BucketeerSyncFingerprints", schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    public func fingerprints(jobID: UUID) async throws -> [String: LocalFileFingerprint] {
        do {
            guard let record = try record(for: jobID) else { return [:] }
            return try JSONDecoder().decode([String: LocalFileFingerprint].self, from: record.fingerprintsData)
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }

    public func replace(jobID: UUID, with fingerprints: [String: LocalFileFingerprint]) async throws {
        do {
            let data = try JSONEncoder().encode(fingerprints)
            if let existing = try record(for: jobID) {
                existing.fingerprintsData = data
            } else {
                modelContext.insert(SyncFingerprintRecord(jobID: jobID, fingerprintsData: data))
            }
            try modelContext.save()
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }

    public func removeAll(except jobIDs: Set<UUID>) async throws {
        do {
            let stale = try modelContext.fetch(FetchDescriptor<SyncFingerprintRecord>())
                .filter { !jobIDs.contains($0.jobID) }
            guard !stale.isEmpty else { return }
            stale.forEach(modelContext.delete)
            try modelContext.save()
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }

    private func record(for jobID: UUID) throws -> SyncFingerprintRecord? {
        try modelContext.fetch(FetchDescriptor<SyncFingerprintRecord>(
            predicate: #Predicate { $0.jobID == jobID }
        )).first
    }
}
