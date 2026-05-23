//
//  S3Object.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation

/// One entry in an object listing. Folders are represented as synthetic
/// items derived from the `CommonPrefixes` portion of `ListObjectsV2` —
/// they have `isFolder = true`, no `etag` (an empty string), size 0, and
/// a `key` that ends with `/`.
struct S3Object: Identifiable, Hashable, Sendable {
    var id: String { key }
    let key: String
    let displayName: String
    let size: Int64
    let lastModified: Date
    let etag: String
    let contentType: String?
    let storageClass: String?
    let isFolder: Bool

    init(
        key: String,
        displayName: String? = nil,
        size: Int64,
        lastModified: Date,
        etag: String,
        contentType: String? = nil,
        storageClass: String? = nil,
        isFolder: Bool = false
    ) {
        self.key = key
        self.displayName = displayName ?? Self.deriveDisplayName(from: key)
        self.size = size
        self.lastModified = lastModified
        self.etag = etag
        self.contentType = contentType
        self.storageClass = storageClass
        self.isFolder = isFolder
    }

    private static func deriveDisplayName(from key: String) -> String {
        let trimmed = key.hasSuffix("/") ? String(key.dropLast()) : key
        return trimmed.split(separator: "/").last.map(String.init) ?? key
    }
}

/// One page of an object listing. Pagination uses S3's continuation token.
struct S3Page: Hashable, Sendable {
    let objects: [S3Object]
    let prefix: String
    let continuationToken: String?
    let hasMore: Bool
}
