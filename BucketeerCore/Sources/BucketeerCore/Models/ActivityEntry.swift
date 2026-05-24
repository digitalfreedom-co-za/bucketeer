//
//  ActivityEntry.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation

/// What kind of operation a row in the activity log represents.
///
/// String-backed so the raw value can be persisted directly in
/// SwiftData and round-tripped through CSV export without losing
/// fidelity. New cases must keep their raw values stable — they
/// double as the persistence format.
public enum ActivityKind: String, Codable, CaseIterable, Sendable {
    case upload
    case download
    case delete
    case createFolder
    case copy
    case presignedURL
    case syncRunStarted
    case syncRunFinished
    case syncRunFailed
    case syncRunCancelled
    case accountAdded
    case accountUpdated
    case accountDeleted
    case mountInstalled
    case mountUninstalled
    case watchFolderTriggered
}

/// Resulting status of an activity row. `info` is the neutral case for
/// events that are neither successes nor failures (e.g. "account
/// added") so the UI can still apply meaningful colouring.
public enum ActivityStatus: String, Codable, CaseIterable, Sendable {
    case info
    case success
    case failure
    case cancelled
}

/// Sendable value snapshot of one activity row. Persisted via
/// `ActivityRecord` and surfaced through `ActivityLogging`.
///
/// Every field except `id`, `kind`, `status`, and `createdAt` is
/// optional because the relevance varies by kind — a `mountInstalled`
/// row has no bucket / key, a `syncRunFinished` row has a job id but
/// no individual object.
public struct ActivityEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let kind: ActivityKind
    public let status: ActivityStatus
    public let createdAt: Date
    public let accountID: UUID?
    public let accountName: String?
    public let bucket: String?
    public let key: String?
    public let byteCount: Int64?
    public let durationMS: Int?
    public let message: String?
    public let errorMessage: String?
    public let syncJobID: UUID?
    public let syncJobName: String?

    public init(
        id: UUID = UUID(),
        kind: ActivityKind,
        status: ActivityStatus,
        createdAt: Date = Date(),
        accountID: UUID? = nil,
        accountName: String? = nil,
        bucket: String? = nil,
        key: String? = nil,
        byteCount: Int64? = nil,
        durationMS: Int? = nil,
        message: String? = nil,
        errorMessage: String? = nil,
        syncJobID: UUID? = nil,
        syncJobName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.createdAt = createdAt
        self.accountID = accountID
        self.accountName = accountName
        self.bucket = bucket
        self.key = key
        self.byteCount = byteCount
        self.durationMS = durationMS
        self.message = message
        self.errorMessage = errorMessage
        self.syncJobID = syncJobID
        self.syncJobName = syncJobName
    }
}
