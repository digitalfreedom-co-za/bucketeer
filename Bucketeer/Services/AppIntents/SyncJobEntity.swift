//
//  SyncJobEntity.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import AppIntents
import BucketeerCore

/// AppIntent-facing wrapper for `SyncJob`. Codex audit R2 (low)
/// follow-up: Shortcuts now picks a job from a typed list keyed on
/// the stable `id`, so a duplicate display name can't make the
/// runner trigger the wrong one.
struct SyncJobEntity: AppEntity, Identifiable, Sendable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Sync Job")
    }

    static let defaultQuery = SyncJobQuery()

    let id: UUID
    let name: String
    let modeRaw: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(modeRaw)")
    }

    init(job: SyncJob) {
        self.id = job.id
        self.name = job.name
        self.modeRaw = job.mode.rawValue
    }
}

/// Feeds the Shortcuts picker. Identical pattern to `AccountQuery`.
struct SyncJobQuery: EntityQuery, Sendable {
    func entities(for identifiers: [UUID]) async throws -> [SyncJobEntity] {
        let all = try await AppIntentsBridge.shared.syncJobs()
        let set = Set(identifiers)
        return all.filter { set.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SyncJobEntity] {
        try await AppIntentsBridge.shared.syncJobs()
    }
}
