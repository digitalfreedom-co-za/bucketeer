//
//  TrashRecord.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import SwiftData

/// SwiftData persistence for the soft-delete trash. Lives in a
/// dedicated container (`BucketeerTrash.store`) — the File Provider
/// extension never has to load this schema and trash writes don't
/// contend with sync-job reads. Phase 13.4.
@Model
public final class TrashRecord {
    @Attribute(.unique) public var id: UUID
    public var accountID: UUID
    public var accountName: String
    public var bucket: String
    public var key: String
    public var size: Int64
    public var contentType: String?
    public var etag: String?
    public var deletedAt: Date
    public var expiresAt: Date
    public var cacheStatusRaw: String
    public var cachedFileName: String?

    public init(item: TrashedItem) {
        self.id = item.id
        self.accountID = item.accountID
        self.accountName = item.accountName
        self.bucket = item.bucket
        self.key = item.key
        self.size = item.size
        self.contentType = item.contentType
        self.etag = item.etag
        self.deletedAt = item.deletedAt
        self.expiresAt = item.expiresAt
        self.cacheStatusRaw = item.cacheStatus.rawValue
        self.cachedFileName = item.cachedFileName
    }

    public var snapshot: TrashedItem? {
        guard let status = TrashCacheStatus(rawValue: cacheStatusRaw) else { return nil }
        return TrashedItem(
            id: id,
            accountID: accountID,
            accountName: accountName,
            bucket: bucket,
            key: key,
            size: size,
            contentType: contentType,
            etag: etag,
            deletedAt: deletedAt,
            expiresAt: expiresAt,
            cacheStatus: status,
            cachedFileName: cachedFileName
        )
    }
}
