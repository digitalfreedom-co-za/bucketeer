//
//  ActivityRecord.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import SwiftData

/// SwiftData persistence model for one activity row. Mirrors
/// `ActivityEntry` 1:1 but uses primitive storage types so the
/// schema is stable and doesn't depend on enum layouts.
///
/// We deliberately keep the activity store separate from the main
/// `Bucketeer.store` (accounts + sync jobs) — see
/// `AppEnvironment.activityStoreFileName`. That isolation means the
/// File Provider extension doesn't have to load the activity schema
/// and audit-log writes never contend with the extension's reads.
@Model
public final class ActivityRecord {
    @Attribute(.unique) public var id: UUID
    public var kindRaw: String
    public var statusRaw: String
    public var createdAt: Date
    public var accountID: UUID?
    public var accountName: String?
    public var bucket: String?
    public var key: String?
    public var byteCount: Int64?
    public var durationMS: Int?
    public var message: String?
    public var errorMessage: String?
    public var syncJobID: UUID?
    public var syncJobName: String?

    public init(entry: ActivityEntry) {
        self.id = entry.id
        self.kindRaw = entry.kind.rawValue
        self.statusRaw = entry.status.rawValue
        self.createdAt = entry.createdAt
        self.accountID = entry.accountID
        self.accountName = entry.accountName
        self.bucket = entry.bucket
        self.key = entry.key
        self.byteCount = entry.byteCount
        self.durationMS = entry.durationMS
        self.message = entry.message
        self.errorMessage = entry.errorMessage
        self.syncJobID = entry.syncJobID
        self.syncJobName = entry.syncJobName
    }

    /// Decode back into a Sendable snapshot. Returns `nil` only if the
    /// persisted `kindRaw` / `statusRaw` doesn't match any current
    /// enum case — i.e. the store was written by a newer version of
    /// the app and the user has downgraded. In that case callers
    /// filter the row out rather than crash.
    public var snapshot: ActivityEntry? {
        guard let kind = ActivityKind(rawValue: kindRaw),
              let status = ActivityStatus(rawValue: statusRaw) else {
            return nil
        }
        return ActivityEntry(
            id: id,
            kind: kind,
            status: status,
            createdAt: createdAt,
            accountID: accountID,
            accountName: accountName,
            bucket: bucket,
            key: key,
            byteCount: byteCount,
            durationMS: durationMS,
            message: message,
            errorMessage: errorMessage,
            syncJobID: syncJobID,
            syncJobName: syncJobName
        )
    }
}
