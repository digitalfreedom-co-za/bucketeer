//
//  SyncJobRecord.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import SwiftData
import BucketeerCore

/// Persistent backing for `SyncJob`. Stored alongside `S3AccountRecord`
/// in the same SwiftData container (Application Support today, App
/// Group container in Phase 9).
@Model
final class SyncJobRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var modeRaw: String

    var sourceAccountID: UUID
    var sourceBucket: String
    var sourcePrefix: String

    var destAccountID: UUID
    var destBucket: String
    var destPrefix: String

    var diffStrategyRaw: String
    var includeGlobs: [String]
    var excludeGlobs: [String]
    var deletePropagation: Bool
    var scheduleRaw: String
    var concurrency: Int
    var lastRunAt: Date?
    var lastRunSummary: String?
    var enabled: Bool

    init(
        id: UUID,
        name: String,
        modeRaw: String,
        sourceAccountID: UUID,
        sourceBucket: String,
        sourcePrefix: String,
        destAccountID: UUID,
        destBucket: String,
        destPrefix: String,
        diffStrategyRaw: String,
        includeGlobs: [String],
        excludeGlobs: [String],
        deletePropagation: Bool,
        scheduleRaw: String,
        concurrency: Int,
        lastRunAt: Date?,
        lastRunSummary: String?,
        enabled: Bool
    ) {
        self.id = id
        self.name = name
        self.modeRaw = modeRaw
        self.sourceAccountID = sourceAccountID
        self.sourceBucket = sourceBucket
        self.sourcePrefix = sourcePrefix
        self.destAccountID = destAccountID
        self.destBucket = destBucket
        self.destPrefix = destPrefix
        self.diffStrategyRaw = diffStrategyRaw
        self.includeGlobs = includeGlobs
        self.excludeGlobs = excludeGlobs
        self.deletePropagation = deletePropagation
        self.scheduleRaw = scheduleRaw
        self.concurrency = concurrency
        self.lastRunAt = lastRunAt
        self.lastRunSummary = lastRunSummary
        self.enabled = enabled
    }

    convenience init(job: SyncJob) {
        self.init(
            id: job.id,
            name: job.name,
            modeRaw: job.mode.rawValue,
            sourceAccountID: job.source.accountID,
            sourceBucket: job.source.bucket,
            sourcePrefix: job.source.prefix,
            destAccountID: job.destination.accountID,
            destBucket: job.destination.bucket,
            destPrefix: job.destination.prefix,
            diffStrategyRaw: job.diffStrategy.rawValue,
            includeGlobs: job.includeGlobs,
            excludeGlobs: job.excludeGlobs,
            deletePropagation: job.deletePropagation,
            scheduleRaw: job.schedule.rawValue,
            concurrency: job.concurrency,
            lastRunAt: job.lastRunAt,
            lastRunSummary: job.lastRunSummary,
            enabled: job.enabled
        )
    }

    func update(from job: SyncJob) {
        name = job.name
        modeRaw = job.mode.rawValue
        sourceAccountID = job.source.accountID
        sourceBucket = job.source.bucket
        sourcePrefix = job.source.prefix
        destAccountID = job.destination.accountID
        destBucket = job.destination.bucket
        destPrefix = job.destination.prefix
        diffStrategyRaw = job.diffStrategy.rawValue
        includeGlobs = job.includeGlobs
        excludeGlobs = job.excludeGlobs
        deletePropagation = job.deletePropagation
        scheduleRaw = job.schedule.rawValue
        concurrency = job.concurrency
        lastRunAt = job.lastRunAt
        lastRunSummary = job.lastRunSummary
        enabled = job.enabled
    }

    var snapshot: SyncJob {
        SyncJob(
            id: id,
            name: name,
            mode: SyncMode(rawValue: modeRaw) ?? .copy,
            source: SyncEndpoint(
                accountID: sourceAccountID,
                bucket: sourceBucket,
                prefix: sourcePrefix
            ),
            destination: SyncEndpoint(
                accountID: destAccountID,
                bucket: destBucket,
                prefix: destPrefix
            ),
            diffStrategy: SyncDiffStrategy(rawValue: diffStrategyRaw) ?? .nameAndSize,
            includeGlobs: includeGlobs,
            excludeGlobs: excludeGlobs,
            deletePropagation: deletePropagation,
            schedule: SyncSchedule(rawValue: scheduleRaw) ?? .manual,
            concurrency: concurrency,
            lastRunAt: lastRunAt,
            lastRunSummary: lastRunSummary,
            enabled: enabled
        )
    }
}
