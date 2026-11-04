//
//  SyncPlanner.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation

/// Pure plan-computation logic for sync jobs. Lifted out of the host's
/// `SyncEngine` so it can be tested without spinning up a real transfer
/// queue and so a future flat-listing primitive in Core can reuse the
/// same comparison/glob-matching rules.
///
/// Has no mutable state and no I/O — every function is `nonisolated`
/// and returns deterministic output for deterministic input. The host
/// engine wires it up between source / destination listing and actual
/// transfer dispatch.
public enum SyncPlanner {

    public struct PlanEntry: Hashable, Sendable {
        /// The source as listed at planning time: its ETag (object
        /// stores) or size and date (local files) identify the version
        /// the entry transfers.
        public let source: S3Object
        public let destinationKey: String

        public var sourceKey: String { source.key }

        public init(source: S3Object, destinationKey: String) {
            self.source = source
            self.destinationKey = destinationKey
        }
    }

    public struct Plan: Sendable {
        public let upserts: [PlanEntry]
        /// Destination-side keys that exist in the destination but not in
        /// the source. Only populated for mirror jobs with
        /// `deletePropagation == true`.
        public let deletes: [String]
        /// Source keys left alone because the destination would store
        /// them under the same name as another key.
        public let collisions: [String]
        /// Source objects whose destination copy is already current.
        public let unchanged: [S3Object]

        public init(upserts: [PlanEntry], deletes: [String], collisions: [String] = [], unchanged: [S3Object] = []) {
            self.upserts = upserts
            self.deletes = deletes
            self.collisions = collisions
            self.unchanged = unchanged
        }
    }

    /// How the destination tells two names apart.
    public enum DestinationNaming: Sendable {
        /// Object keys: byte for byte.
        case exact
        /// A local folder: APFS ignores Unicode normalisation, and most
        /// volumes also ignore case.
        case fileSystem(caseSensitive: Bool)

        func identity(of name: String) -> String {
            switch self {
            case .exact:
                return name
            case .fileSystem(let caseSensitive):
                let normalized = name.precomposedStringWithCanonicalMapping
                return caseSensitive ? normalized : normalized.folding(options: .caseInsensitive, locale: nil)
            }
        }
    }

    /// Compute the set of upserts and (for mirror jobs with delete
    /// propagation) deletes. Pure function — same inputs, same plan.
    /// Works for any combination of S3 / local endpoints: caller
    /// enumerates each side into a `[S3Object]` (local folders use
    /// `LocalFolderEnumerator` with empty `etag` and relative-path
    /// keys; S3 / Azure use the existing recursive listing).
    ///
    /// `acknowledged` holds the fingerprints a local source had when the
    /// job last synced it (empty for a job that never recorded any).
    public static func makePlan(
        job: SyncJob,
        source: [S3Object],
        destination: [S3Object],
        destinationNaming naming: DestinationNaming = .exact,
        acknowledged: [String: LocalFileFingerprint] = [:]
    ) -> Plan {
        let sourceIsLocal = if case .localFolder = job.source { true } else { false }
        let sourcePrefix = prefix(for: job.source)
        let destinationPrefix = prefix(for: job.destination)

        let destIndex: [String: S3Object] = Dictionary(
            uniqueKeysWithValues: destination.map { ($0.key, $0) }
        )
        let destinationNames = Dictionary(
            destination.filter { !$0.isFolder }.map { (naming.identity(of: $0.key), [$0.key]) },
            uniquingKeysWith: +
        )

        let candidates = source.filter { s in
            guard !s.isFolder else { return false }
            let relative = relativeKey(s.key, under: sourcePrefix)
            return !relative.isEmpty
                && matches(relative, includes: job.includeGlobs, excludes: job.excludeGlobs)
        }
        let candidatesPerName = Dictionary(
            grouping: candidates,
            by: { naming.identity(of: destinationPrefix + relativeKey($0.key, under: sourcePrefix)) }
        )

        var upserts: [PlanEntry] = []
        var collisions: [String] = []
        var unchanged: [S3Object] = []
        for s in candidates {
            let destKey = destinationPrefix + relativeKey(s.key, under: sourcePrefix)
            let name = naming.identity(of: destKey)
            // Two source keys, or a source key and a differently spelled
            // destination file, would land on one file: writing either
            // would silently replace the other.
            let sharesName = candidatesPerName[name, default: []].count > 1
                || destinationNames[name, default: []].contains { $0 != destKey }
            if sharesName {
                collisions.append(s.key)
                continue
            }
            if let existing = destIndex[destKey],
               isUnchanged(source: s, dest: existing, strategy: job.diffStrategy),
               !sourceIsLocal || isAcknowledged(s, copy: existing, acknowledged: acknowledged[s.key]) {
                unchanged.append(s)
                continue
            }
            upserts.append(PlanEntry(source: s, destinationKey: destKey))
        }

        var deletes: [String] = []
        if job.mode == .mirror && job.deletePropagation {
            // Destination-side keys whose corresponding relative path is
            // absent from the source. Filtered by the same include/exclude
            // globs as the upsert side so a mirror job for `*.jpg`
            // never deletes unrelated files in the destination. A file
            // the source names in another spelling is not an orphan.
            let sourceRelatives = Set(
                source
                    .filter { !$0.isFolder }
                    .map { naming.identity(of: relativeKey($0.key, under: sourcePrefix)) }
            )
            for d in destination where !d.isFolder {
                let relative = relativeKey(d.key, under: destinationPrefix)
                guard matches(relative, includes: job.includeGlobs, excludes: job.excludeGlobs) else {
                    continue
                }
                if !sourceRelatives.contains(naming.identity(of: relative)) {
                    deletes.append(d.key)
                }
            }
        }

        return Plan(upserts: upserts, deletes: deletes, collisions: collisions, unchanged: unchanged)
    }

    /// A local file has no ETag, so an equal size alone cannot tell an
    /// edit apart. It counts as synced only if it still has the
    /// fingerprint the job acknowledged — or, before any fingerprint
    /// was recorded, if it is not newer than its copy.
    static func isAcknowledged(
        _ file: S3Object,
        copy: S3Object,
        acknowledged: LocalFileFingerprint?
    ) -> Bool {
        if let acknowledged { return acknowledged == LocalFileFingerprint(file) }
        return file.lastModified <= copy.lastModified
    }

    /// Effective prefix for a sync endpoint. S3 endpoints carry an
    /// in-bucket prefix; local folders have no concept of one (the
    /// `LocalFolderEnumerator` already yields keys relative to the
    /// folder root). Returning `""` for local is the right neutral
    /// element for `relativeKey`.
    public static func prefix(for endpoint: SyncEndpoint) -> String {
        if case .s3(_, _, let prefix) = endpoint { return prefix }
        return ""
    }

    // MARK: - Internal helpers (public so tests in BucketeerCoreTests can poke them)

    public static func relativeKey(_ key: String, under prefix: String) -> String {
        guard !prefix.isEmpty, key.hasPrefix(prefix) else { return key }
        return String(key.dropFirst(prefix.count))
    }

    public static func isUnchanged(
        source: S3Object,
        dest: S3Object,
        strategy: SyncDiffStrategy
    ) -> Bool {
        switch strategy {
        case .nameAndSize:
            return source.size == dest.size
        case .nameAndEtag:
            return !source.etag.isEmpty && source.etag == dest.etag
        }
    }

    public static func matches(
        _ relative: String,
        includes: [String],
        excludes: [String]
    ) -> Bool {
        if !excludes.isEmpty {
            for pattern in excludes where glob(relative, matches: pattern) {
                return false
            }
        }
        if !includes.isEmpty {
            return includes.contains { glob(relative, matches: $0) }
        }
        return true
    }

    /// Minimal POSIX-glob matching (?, *) for include/exclude patterns.
    /// Backed by NSPredicate's LIKE clause — handles `?` (single char)
    /// and `*` (any chars including none).
    public static func glob(_ value: String, matches pattern: String) -> Bool {
        let predicate = NSPredicate(format: "SELF LIKE %@", pattern)
        return predicate.evaluate(with: value)
    }
}
