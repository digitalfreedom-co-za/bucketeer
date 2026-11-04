//
//  LocalFileFingerprint.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import SwiftData

/// Size and modification date of a local file as a sync job last
/// transferred (or confirmed) it. Every save changes the modification
/// date, so an edit that keeps the size is still noticed; a touch
/// without an edit only costs one extra upload.
public struct LocalFileFingerprint: Codable, Hashable, Sendable {
    public let size: Int64
    public let modified: Date

    public init(size: Int64, modified: Date) {
        self.size = size
        self.modified = modified
    }

    /// Fingerprint of a file as `LocalFolderEnumerator` listed it.
    public init(_ file: S3Object) {
        self.init(size: file.size, modified: file.lastModified)
    }
}

/// One row per sync job: the acknowledged fingerprints of its local
/// source, keyed by relative path, JSON-encoded. Host-only store.
@Model
public final class SyncFingerprintRecord {
    @Attribute(.unique) public var jobID: UUID
    var fingerprintsData: Data

    init(jobID: UUID, fingerprintsData: Data) {
        self.jobID = jobID
        self.fingerprintsData = fingerprintsData
    }
}
