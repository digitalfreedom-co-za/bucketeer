//
//  SyncJob.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation

/// Identifies a source or destination scope within one account.
struct SyncEndpoint: Codable, Hashable, Sendable {
    let accountID: UUID
    var bucket: String
    /// Always normalised to either empty or trailing-slash, mirroring
    /// the `prefix` semantics used everywhere else in the app.
    var prefix: String
}

/// Operational mode for a sync job.
enum SyncMode: String, Codable, CaseIterable, Sendable {
    /// One-shot duplication. Source remains untouched; destination
    /// receives a copy of every matching object.
    case copy
    /// Like `copy` but the source object is deleted after each
    /// successful transfer.
    case move
    /// Continuous one-way mirror — additions and updates are propagated
    /// from source to destination on every run. Deletes on the source
    /// only propagate when `deletePropagation == true`, and only after
    /// a confirmation dialog on the very first run with deletes pending.
    case mirror
}

/// When a job is allowed to run automatically. Manual jobs only run
/// when the user clicks "Run Now". On-launch jobs run once each app
/// start. Interval jobs run every N seconds while the app is awake.
enum SyncSchedule: Codable, Hashable, Sendable {
    case manual
    case onLaunch
    case interval(seconds: Int)

    /// Stored as a single string in SwiftData. Format:
    /// - `manual`
    /// - `onLaunch`
    /// - `interval=3600`
    var rawValue: String {
        switch self {
        case .manual:                 return "manual"
        case .onLaunch:               return "onLaunch"
        case .interval(let seconds):  return "interval=\(seconds)"
        }
    }

    init?(rawValue: String) {
        if rawValue == "manual" { self = .manual; return }
        if rawValue == "onLaunch" { self = .onLaunch; return }
        if rawValue.hasPrefix("interval="),
           let seconds = Int(rawValue.dropFirst("interval=".count)) {
            self = .interval(seconds: seconds); return
        }
        return nil
    }
}

/// Diff comparison strategy. `nameAndSize` is fast and accurate enough
/// for most workloads; `nameAndEtag` catches in-place edits that keep
/// the size constant. Cross-provider mirrors can only use `nameAndSize`
/// because ETag formats differ between S3 and Azure.
enum SyncDiffStrategy: String, Codable, CaseIterable, Sendable {
    case nameAndSize
    case nameAndEtag
}

/// Sendable value snapshot of a sync job. Stored in SwiftData via
/// `SyncJobRecord`.
struct SyncJob: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var mode: SyncMode
    var source: SyncEndpoint
    var destination: SyncEndpoint
    var diffStrategy: SyncDiffStrategy
    var includeGlobs: [String]
    var excludeGlobs: [String]
    var deletePropagation: Bool
    var schedule: SyncSchedule
    var concurrency: Int
    var lastRunAt: Date?
    var lastRunSummary: String?
    var enabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        mode: SyncMode = .copy,
        source: SyncEndpoint,
        destination: SyncEndpoint,
        diffStrategy: SyncDiffStrategy = .nameAndSize,
        includeGlobs: [String] = [],
        excludeGlobs: [String] = [],
        deletePropagation: Bool = false,
        schedule: SyncSchedule = .manual,
        concurrency: Int = 4,
        lastRunAt: Date? = nil,
        lastRunSummary: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.source = source
        self.destination = destination
        self.diffStrategy = diffStrategy
        self.includeGlobs = includeGlobs
        self.excludeGlobs = excludeGlobs
        self.deletePropagation = deletePropagation
        self.schedule = schedule
        self.concurrency = concurrency
        self.lastRunAt = lastRunAt
        self.lastRunSummary = lastRunSummary
        self.enabled = enabled
    }
}

/// Live status of a job — surfaced through `SyncEngine.statuses` so the
/// list view can render running / queued state without polling.
struct SyncJobStatus: Identifiable, Hashable, Sendable {
    var id: UUID { jobID }
    let jobID: UUID
    var phase: Phase
    var planned: Int
    var completed: Int
    var failed: Int
    var startedAt: Date?
    var message: String?

    enum Phase: String, Hashable, Sendable {
        case idle
        case planning
        case awaitingConfirmation
        case running
        case finished
        case failed
        case cancelled
    }
}
