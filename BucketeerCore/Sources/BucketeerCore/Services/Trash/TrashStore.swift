//
//  TrashStore.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import SwiftData

/// SwiftData + filesystem-backed implementation of `TrashStoring`.
/// Phase 13.4.
///
/// Manual `ModelActor` conformance (rather than the `@ModelActor`
/// macro) because the store needs a custom init that also takes a
/// `cacheRootURL` for the on-disk payload directory. The two
/// resources are kept in lockstep — every code path that deletes a
/// record also deletes the corresponding file.
public actor TrashStore: TrashStoring, ModelActor {
    public nonisolated let modelExecutor: any ModelExecutor
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let cacheRootURL: URL

    public init(modelContainer: ModelContainer, cacheRootURL: URL) {
        let context = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = modelContainer
        self.cacheRootURL = cacheRootURL
        // Best-effort cache-directory creation.
        try? FileManager.default.createDirectory(
            at: cacheRootURL,
            withIntermediateDirectories: true
        )
    }

    // MARK: - TrashStoring

    public func record(_ item: TrashedItem) async {
        do {
            modelContext.insert(TrashRecord(item: item))
            try modelContext.save()
        } catch {
            // Trash recording is observation. Never block the
            // underlying delete on persistence failure.
        }
    }

    public func markCached(id: UUID, fileName: String) async {
        do {
            let descriptor = FetchDescriptor<TrashRecord>(
                predicate: #Predicate { $0.id == id }
            )
            if let record = try modelContext.fetch(descriptor).first {
                record.cacheStatusRaw = TrashCacheStatus.cached.rawValue
                record.cachedFileName = fileName
                try modelContext.save()
            }
        } catch {
            // Silent — same rationale as `record`.
        }
    }

    public func markStatus(id: UUID, status: TrashCacheStatus) async {
        do {
            let descriptor = FetchDescriptor<TrashRecord>(
                predicate: #Predicate { $0.id == id }
            )
            if let record = try modelContext.fetch(descriptor).first {
                record.cacheStatusRaw = status.rawValue
                try modelContext.save()
            }
        } catch {}
    }

    public func recent(limit: Int) async throws -> [TrashedItem] {
        do {
            var descriptor = FetchDescriptor<TrashRecord>(
                sortBy: [SortDescriptor(\.deletedAt, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            return try modelContext.fetch(descriptor).compactMap(\.snapshot)
        } catch {
            throw BucketeerError.persistenceFailure(
                message: error.localizedDescription
            )
        }
    }

    public func count() async throws -> Int {
        do {
            return try modelContext.fetchCount(FetchDescriptor<TrashRecord>())
        } catch {
            throw BucketeerError.persistenceFailure(
                message: error.localizedDescription
            )
        }
    }

    public func forget(id: UUID) async throws {
        do {
            let descriptor = FetchDescriptor<TrashRecord>(
                predicate: #Predicate { $0.id == id }
            )
            guard let record = try modelContext.fetch(descriptor).first else { return }
            if let name = record.cachedFileName {
                try? FileManager.default.removeItem(
                    at: cacheRootURL.appendingPathComponent(name)
                )
            }
            modelContext.delete(record)
            try modelContext.save()
        } catch {
            throw BucketeerError.persistenceFailure(
                message: error.localizedDescription
            )
        }
    }

    public func empty() async throws {
        do {
            let all = try modelContext.fetch(FetchDescriptor<TrashRecord>())
            for record in all {
                if let name = record.cachedFileName {
                    try? FileManager.default.removeItem(
                        at: cacheRootURL.appendingPathComponent(name)
                    )
                }
                modelContext.delete(record)
            }
            try modelContext.save()
        } catch {
            throw BucketeerError.persistenceFailure(
                message: error.localizedDescription
            )
        }
    }

    public func purgeExpired() async {
        let now = Date()
        do {
            let expired = try modelContext.fetch(
                FetchDescriptor<TrashRecord>(
                    predicate: #Predicate { $0.expiresAt < now }
                )
            )
            for record in expired {
                if let name = record.cachedFileName {
                    try? FileManager.default.removeItem(
                        at: cacheRootURL.appendingPathComponent(name)
                    )
                }
                modelContext.delete(record)
            }
            try modelContext.save()
        } catch {
            // Best-effort housekeeping. Never block launch.
        }
    }
}
