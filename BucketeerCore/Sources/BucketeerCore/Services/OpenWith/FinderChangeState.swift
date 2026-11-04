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
    /// Key → unquoted ETag (`""` for folders) of what the system has
    /// been given: the last change listing plus every item a folder
    /// enumeration delivered since.
    public private(set) var entries: [String: String] = [:]
    /// Bumped on every change, so a caller that read the state before
    /// an await can tell whether somebody changed it meanwhile.
    public private(set) var revision = 0

    public init(anchor: String) {
        self.anchor = anchor
    }

    /// Returns `true` when the prefix was not tracked yet.
    @discardableResult
    public mutating func track(prefix: String) -> Bool {
        let inserted = trackedPrefixes.insert(prefix).inserted
        if inserted { revision += 1 }
        return inserted
    }

    /// A folder enumeration handed these items (key → ETag, one page of
    /// `prefix`) to the system. They join the baseline, so a later
    /// deletion of any of them is reported.
    public mutating func record(_ delivered: [String: String], under prefix: String) {
        track(prefix: prefix)
        for (key, etag) in delivered where Self.parent(of: key) == prefix {
            entries[key] = ETag.normalized(etag)
        }
        revision += 1
    }

    /// The system was given this item outside an enumeration (the
    /// result of a create, modify or fetch). Only items of folders
    /// Finder has open are kept; the others are not part of the baseline.
    public mutating func remember(_ key: String, etag: String) {
        guard trackedPrefixes.contains(Self.parent(of: key)) else { return }
        entries[key] = ETag.normalized(etag)
        revision += 1
    }

    /// Key → ETag of every file below `prefix` as the system was given it.
    public func knownVersions(under prefix: String) -> [String: String] {
        entries.filter { $0.key.hasPrefix(prefix) && !$0.key.hasSuffix("/") }
    }

    /// Replaces the remembered entries of `listedPrefixes` with
    /// `listing` and returns what changed. Entries of other prefixes
    /// (tracked after the listing was taken) stay as they are and
    /// produce no changes.
    public mutating func advance(
        to listing: [String: String],
        listedPrefixes: Set<String>,
        anchor newAnchor: String
    ) -> ListingDiff {
        let fresh = listing
            .filter { listedPrefixes.contains(Self.parent(of: $0.key)) }
            .mapValues(ETag.normalized)
        let updated = fresh.filter { entries[$0.key] != $0.value }.map(\.key).sorted()
        let deleted = entries.keys
            .filter { listedPrefixes.contains(Self.parent(of: $0)) && fresh[$0] == nil }
            .sorted()
        for key in deleted { entries.removeValue(forKey: key) }
        entries.merge(fresh) { _, new in new }
        anchor = newAnchor
        revision += 1
        pruneVanishedFolders()
        return ListingDiff(updated: updated, deleted: deleted)
    }

    /// A folder whose parent is tracked but which no longer shows up in
    /// that parent's listing is gone; stop listing it and forget what
    /// was under it.
    private mutating func pruneVanishedFolders() {
        trackedPrefixes = trackedPrefixes.filter { prefix in
            prefix.isEmpty
                || !trackedPrefixes.contains(Self.parent(of: prefix))
                || entries[prefix] != nil
        }
        entries = entries.filter { trackedPrefixes.contains(Self.parent(of: $0.key)) }
    }

    static func parent(of prefix: String) -> String {
        let trimmed = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        guard let slash = trimmed.lastIndex(of: "/") else { return "" }
        return String(trimmed[...slash])
    }
}
