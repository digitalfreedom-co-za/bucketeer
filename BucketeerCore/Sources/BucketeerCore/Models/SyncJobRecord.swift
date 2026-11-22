//
//  SyncJobRecord.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import SwiftData

/// Persistent backing for `SyncJob`. Stored alongside `S3AccountRecord`
/// in the shared SwiftData container (see `SharedStore`). Lives in Core
/// so the File Provider extension opens the store with the same schema
/// as the host.
///
/// Phase 9.8 changed the endpoint representation from three flat S3
/// columns to a single JSON-encoded `SyncEndpoint` enum, so a sync
/// job's source or destination can be either an S3 scope or a local
/// folder bookmark. Storing as JSON keeps the SwiftData schema simple
/// (one `Data` field per side) without adding a flock of optional
/// type-specific columns.
@Model
public final class SyncJobRecord {
    @Attribute(.unique) public var id: UUID
    public var name: String
    var modeRaw: String

    /// JSON-encoded `SyncEndpoint` for the source.
    var sourceEndpointData: Data
    /// JSON-encoded `SyncEndpoint` for the destination.
    var destinationEndpointData: Data

    var diffStrategyRaw: String
    var includeGlobs: [String]
    var excludeGlobs: [String]
    var deletePropagation: Bool
    /// Added after the first release; the default lets stores written
    /// before it migrate with the option off.
    var allowsDecryptedCopies: Bool = false
    var scheduleRaw: String
    var concurrency: Int
    public var lastRunAt: Date?
    public var lastRunSummary: String?
    var enabled: Bool

    init(
        id: UUID,
        name: String,
        modeRaw: String,
        sourceEndpointData: Data,
        destinationEndpointData: Data,
        diffStrategyRaw: String,
        includeGlobs: [String],
        excludeGlobs: [String],
        deletePropagation: Bool,
        allowsDecryptedCopies: Bool,
        scheduleRaw: String,
        concurrency: Int,
        lastRunAt: Date?,
        lastRunSummary: String?,
        enabled: Bool
    ) {
        self.id = id
        self.name = name
        self.modeRaw = modeRaw
        self.sourceEndpointData = sourceEndpointData
        self.destinationEndpointData = destinationEndpointData
        self.diffStrategyRaw = diffStrategyRaw
        self.includeGlobs = includeGlobs
        self.excludeGlobs = excludeGlobs
        self.deletePropagation = deletePropagation
        self.allowsDecryptedCopies = allowsDecryptedCopies
        self.scheduleRaw = scheduleRaw
        self.concurrency = concurrency
        self.lastRunAt = lastRunAt
        self.lastRunSummary = lastRunSummary
        self.enabled = enabled
    }

    public convenience init(job: SyncJob) {
        // SyncEndpoint is Codable; JSON-encoding is deterministic
        // enough for storage (no version drift expected for an enum
        // with two cases). Falls back to empty Data on encode failure
        // — the snapshot getter then surfaces nil and the host treats
        // the record as broken and refuses to run it.
        let encoder = JSONEncoder()
        let sourceData = (try? encoder.encode(job.source)) ?? Data()
        let destData = (try? encoder.encode(job.destination)) ?? Data()
        self.init(
            id: job.id,
            name: job.name,
            modeRaw: job.mode.rawValue,
            sourceEndpointData: sourceData,
            destinationEndpointData: destData,
            diffStrategyRaw: job.diffStrategy.rawValue,
            includeGlobs: job.includeGlobs,
            excludeGlobs: job.excludeGlobs,
            deletePropagation: job.deletePropagation,
            allowsDecryptedCopies: job.allowsDecryptedCopies,
            scheduleRaw: job.schedule.rawValue,
            concurrency: job.concurrency,
            lastRunAt: job.lastRunAt,
            lastRunSummary: job.lastRunSummary,
            enabled: job.enabled
        )
    }

    public func update(from job: SyncJob) {
        let encoder = JSONEncoder()
        name = job.name
        modeRaw = job.mode.rawValue
        if let data = try? encoder.encode(job.source) {
            sourceEndpointData = data
        }
        if let data = try? encoder.encode(job.destination) {
            destinationEndpointData = data
        }
        diffStrategyRaw = job.diffStrategy.rawValue
        includeGlobs = job.includeGlobs
        excludeGlobs = job.excludeGlobs
        deletePropagation = job.deletePropagation
        allowsDecryptedCopies = job.allowsDecryptedCopies
        scheduleRaw = job.schedule.rawValue
        concurrency = job.concurrency
        lastRunAt = job.lastRunAt
        lastRunSummary = job.lastRunSummary
        enabled = job.enabled
    }

    /// Sendable snapshot. Returns `nil` when one of the endpoint blobs
    /// fails to decode — that record is then treated as broken and
    /// hidden from the UI rather than crashing the list.
    public var snapshot: SyncJob? {
        let decoder = JSONDecoder()
        guard
            let source = try? decoder.decode(SyncEndpoint.self, from: sourceEndpointData),
            let destination = try? decoder.decode(SyncEndpoint.self, from: destinationEndpointData)
        else { return nil }
        return SyncJob(
            id: id,
            name: name,
            mode: SyncMode(rawValue: modeRaw) ?? .copy,
            source: source,
            destination: destination,
            diffStrategy: SyncDiffStrategy(rawValue: diffStrategyRaw) ?? .nameAndSize,
            includeGlobs: includeGlobs,
            excludeGlobs: excludeGlobs,
            deletePropagation: deletePropagation,
            allowsDecryptedCopies: allowsDecryptedCopies,
            schedule: SyncSchedule(rawValue: scheduleRaw) ?? .manual,
            concurrency: concurrency,
            lastRunAt: lastRunAt,
            lastRunSummary: lastRunSummary,
            enabled: enabled
        )
    }
}
