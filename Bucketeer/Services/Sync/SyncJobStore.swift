//
//  SyncJobStore.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import SwiftData
import BucketeerCore

/// CRUD facade for `SyncJobRecord`. Mirrors the pattern used by
/// `AccountStore`: only `SyncJob` value snapshots cross the actor
/// boundary out, never the `@Model` reference.
protocol SyncJobStoring: Sendable {
    func all() async throws -> [SyncJob]
    func upsert(_ job: SyncJob) async throws
    func delete(id: UUID) async throws
    func touchLastRun(id: UUID, at: Date, summary: String?) async throws
}

@ModelActor
actor SyncJobStore: SyncJobStoring {

    func all() async throws -> [SyncJob] {
        do {
            let descriptor = FetchDescriptor<SyncJobRecord>(
                sortBy: [SortDescriptor(\.name)]
            )
            // `snapshot` is Optional<SyncJob> now that endpoints are
            // stored as JSON: records whose endpoint blob fails to
            // decode (corrupted store, schema-incompatible old data)
            // are silently filtered out so the UI never crashes on
            // them. Codex deep-audit dead-code rule: this is the
            // only place the corrupted record matters.
            return try modelContext.fetch(descriptor).compactMap(\.snapshot)
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }

    func upsert(_ job: SyncJob) async throws {
        do {
            let id = job.id
            let existing = try modelContext.fetch(
                FetchDescriptor<SyncJobRecord>(predicate: #Predicate { $0.id == id })
            ).first
            if let existing {
                existing.update(from: job)
            } else {
                modelContext.insert(SyncJobRecord(job: job))
            }
            try modelContext.save()
        } catch let error as BucketeerError {
            throw error
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }

    func delete(id: UUID) async throws {
        do {
            if let record = try modelContext.fetch(
                FetchDescriptor<SyncJobRecord>(predicate: #Predicate { $0.id == id })
            ).first {
                modelContext.delete(record)
                try modelContext.save()
            }
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }

    func touchLastRun(id: UUID, at: Date, summary: String?) async throws {
        do {
            if let record = try modelContext.fetch(
                FetchDescriptor<SyncJobRecord>(predicate: #Predicate { $0.id == id })
            ).first {
                record.lastRunAt = at
                record.lastRunSummary = summary
                try modelContext.save()
            }
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }
}
