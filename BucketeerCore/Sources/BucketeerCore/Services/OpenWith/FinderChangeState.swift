//
//  FinderChangeState.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation

public struct ListingDiff: Equatable, Sendable {
    public let updated: [String]
    public let deleted: [String]

    public init(updated: [String], deleted: [String]) {
        self.updated = updated
        self.deleted = deleted
    }
}

/// Change tracking for a mounted bucket. S3 and Azure have no change
/// feed, so the File Provider extension remembers the last listing
/// (key → ETag) of every folder Finder has opened, lists those folders
/// again when asked for changes, and reports the difference. The
/// anchor identifies the listing the system last saw; an anchor that
/// does not match means the state was lost and the system must
/// re-enumerate.
public struct FinderChangeState: Codable, Equatable, Sendable {
    public private(set) var anchor: String
    /// Folder prefixes Finder has enumerated; `""` is the bucket root.
    public private(set) var trackedPrefixes: Set<String> = [""]
    /// Key → unquoted ETag (`""` for folders) of the last listing.
    public private(set) var entries: [String: String] = [:]

    public init(anchor: String) {
        self.anchor = anchor
    }

    /// Returns `true` when the prefix was not tracked yet.
    @discardableResult
    public mutating func track(prefix: String) -> Bool {
        trackedPrefixes.insert(prefix).inserted
    }

    /// Replaces the remembered listing with `listing` (the fresh
    /// listing of all tracked prefixes) and returns what changed.
    public mutating func advance(to listing: [String: String], anchor newAnchor: String) -> ListingDiff {
        let fresh = listing.mapValues(ETag.normalized)
        let updated = fresh.filter { entries[$0.key] != $0.value }.map(\.key).sorted()
        let deleted = entries.keys.filter { fresh[$0] == nil }.sorted()
        entries = fresh
        anchor = newAnchor
        pruneVanishedFolders()
        return ListingDiff(updated: updated, deleted: deleted)
    }

    /// A folder whose parent is tracked but which no longer shows up in
    /// that parent's listing is gone; stop listing it.
    private mutating func pruneVanishedFolders() {
        trackedPrefixes = trackedPrefixes.filter { prefix in
            prefix.isEmpty
                || !trackedPrefixes.contains(Self.parent(of: prefix))
                || entries[prefix] != nil
        }
    }

    static func parent(of prefix: String) -> String {
        let trimmed = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        guard let slash = trimmed.lastIndex(of: "/") else { return "" }
        return String(trimmed[...slash])
    }
}
