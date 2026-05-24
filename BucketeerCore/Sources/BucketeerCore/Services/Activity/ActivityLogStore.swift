//
//  ActivityLogStore.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import SwiftData

/// SwiftData-backed `ActivityLogging` implementation. Lives in its own
/// `ModelContainer` (see `AppContainer.makeActivityContainer`) so
/// audit writes don't share contention with the accounts / sync-jobs
/// store and the File Provider extension never has to load this
/// schema.
///
/// `record(_:)` deliberately swallows storage errors — recording is
/// observation, not the operation itself, so a transient SwiftData
/// failure must never turn a successful upload into a user-visible
/// failure.
@ModelActor
public actor ActivityLogStore: ActivityLogging {

    public func record(_ entry: ActivityEntry) async {
        do {
            modelContext.insert(ActivityRecord(entry: entry))
            try modelContext.save()
        } catch {
            // Intentionally silent. See doc comment.
        }
    }

    public func recent(limit: Int) async throws -> [ActivityEntry] {
        try fetch(limit: limit, predicate: nil)
    }

    public func search(
        text: String?,
        kinds: Set<ActivityKind>?,
        accountID: UUID?,
        limit: Int
    ) async throws -> [ActivityEntry] {
        var results = try fetch(limit: limit * 4, predicate: nil)
        if let kinds, !kinds.isEmpty {
            let allowed = Set(kinds.map(\.rawValue))
            results = results.filter { allowed.contains($0.kind.rawValue) }
        }
        if let accountID {
            results = results.filter { $0.accountID == accountID }
        }
        if let text, !text.isEmpty {
            let needle = text.lowercased()
            results = results.filter { entry in
                let haystacks: [String?] = [
                    entry.bucket,
                    entry.key,
                    entry.accountName,
                    entry.syncJobName,
                    entry.message,
                    entry.errorMessage
                ]
                return haystacks.contains { ($0 ?? "").lowercased().contains(needle) }
            }
        }
        return Array(results.prefix(limit))
    }

    public func deleteAll() async throws {
        do {
            try modelContext.delete(model: ActivityRecord.self)
            try modelContext.save()
        } catch {
            throw BucketeerError.persistenceFailure(
                message: error.localizedDescription
            )
        }
    }

    public func purgeExpired(retentionDays: Int) async {
        guard retentionDays > 0 else { return }
        let cutoff = Date().addingTimeInterval(
            -Double(retentionDays) * 24 * 60 * 60
        )
        do {
            try modelContext.delete(
                model: ActivityRecord.self,
                where: #Predicate<ActivityRecord> { $0.createdAt < cutoff }
            )
            try modelContext.save()
        } catch {
            // Best-effort housekeeping. Never block launch.
        }
    }

    public func count() async throws -> Int {
        do {
            return try modelContext.fetchCount(
                FetchDescriptor<ActivityRecord>()
            )
        } catch {
            throw BucketeerError.persistenceFailure(
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Private

    private func fetch(
        limit: Int,
        predicate: Predicate<ActivityRecord>?
    ) throws -> [ActivityEntry] {
        do {
            var descriptor = FetchDescriptor<ActivityRecord>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            return try modelContext
                .fetch(descriptor)
                .compactMap(\.snapshot)
        } catch {
            throw BucketeerError.persistenceFailure(
                message: error.localizedDescription
            )
        }
    }
}
