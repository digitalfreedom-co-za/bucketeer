//
//  ObjectVersion.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation

/// One historical revision of an object on a versioning-enabled
/// bucket. Surfaced by `S3Browsing.listVersions` so the versions
/// browser (Phase 13.6) can show users every recorded edit and
/// optional delete-marker.
///
/// Azure Blob snapshots map onto this struct the same way: the
/// snapshot timestamp goes into `versionId` and the marker-of-
/// deletion flag stays `false` because Azure expresses deletes
/// differently (soft delete is a separate feature).
public struct ObjectVersion: Identifiable, Hashable, Sendable {
    public let key: String
    /// Provider-specific version identifier. Required to GET, COPY,
    /// or DELETE a specific version. Opaque to the UI.
    public let versionId: String
    public let isLatest: Bool
    /// `true` for an S3 *delete marker* — there's no payload to
    /// restore as-is, but removing the delete marker effectively
    /// undeletes the object back to whatever version preceded it.
    public let isDeleteMarker: Bool
    public let size: Int64
    public let lastModified: Date
    public let etag: String?
    public let storageClass: String?

    public var id: String { "\(key)|\(versionId)" }

    public init(
        key: String,
        versionId: String,
        isLatest: Bool,
        isDeleteMarker: Bool,
        size: Int64,
        lastModified: Date,
        etag: String?,
        storageClass: String?
    ) {
        self.key = key
        self.versionId = versionId
        self.isLatest = isLatest
        self.isDeleteMarker = isDeleteMarker
        self.size = size
        self.lastModified = lastModified
        self.etag = etag
        self.storageClass = storageClass
    }
}
