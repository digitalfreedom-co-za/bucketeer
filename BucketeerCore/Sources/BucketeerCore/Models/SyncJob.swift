//
//  SyncJob.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation

/// Identifies a source or destination scope within one account.
public struct SyncEndpoint: Codable, Hashable, Sendable {
    public let accountID: UUID
    public var bucket: String
    /// Always normalised to either empty or trailing-slash, mirroring
    /// the `prefix` semantics used everywhere else in the app.
    public var prefix: String

    public init(accountID: UUID, bucket: String, prefix: String = "") {
        self.accountID = accountID
        self.bucket = bucket
        self.prefix = prefix
    }
}

/// Operational mode for a sync job.
public enum SyncMode: String, Codable, CaseIterable, Sendable {
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
public enum SyncSchedule: Codable, Hashable, Sendable {
    case manual
    case onLaunch
    case interval(seconds: Int)

    /// Stored as a single string in SwiftData. Format:
    /// - `manual`
    /// - `onLaunch`
    /// - `interval=3600`
    public var rawValue: String {
        switch self {
        case .manual:                 return "manual"
        case .onLaunch:               return "onLaunch"
        case .interval(let seconds):  return "interval=\(seconds)"
        }
    }

    public init?(rawValue: String) {
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
public enum SyncDiffStrategy: String, Codable, CaseIterable, Sendable {
    case nameAndSize
    case nameAndEtag
}

/// Sendable value snapshot of a sync job. Stored in SwiftData via
/// `SyncJobRecord`.
public struct SyncJob: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var mode: SyncMode
    public var source: SyncEndpoint
    public var destination: SyncEndpoint
    public var diffStrategy: SyncDiffStrategy
    public var includeGlobs: [String]
    public var excludeGlobs: [String]
    public var deletePropagation: Bool
    public var schedule: SyncSchedule
    public var concurrency: Int
    public var lastRunAt: Date?
    public var lastRunSummary: String?
    public var enabled: Bool

    public init(
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
public struct SyncJobStatus: Identifiable, Hashable, Sendable {
    public var id: UUID { jobID }
    public let jobID: UUID
    public var phase: Phase
    public var planned: Int
    public var completed: Int
    public var failed: Int
    public var startedAt: Date?
    public var message: String?

    public enum Phase: String, Hashable, Sendable {
        case idle
        case planning
        case awaitingConfirmation
        case running
        case finished
        case failed
        case cancelled
    }

    public init(
        jobID: UUID,
        phase: Phase,
        planned: Int = 0,
        completed: Int = 0,
        failed: Int = 0,
        startedAt: Date? = nil,
        message: String? = nil
    ) {
        self.jobID = jobID
        self.phase = phase
        self.planned = planned
        self.completed = completed
        self.failed = failed
        self.startedAt = startedAt
        self.message = message
    }
}