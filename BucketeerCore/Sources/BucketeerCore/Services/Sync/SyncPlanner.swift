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
        public let sourceKey: String
        public let sourceSize: Int64
        public let destinationKey: String

        public init(sourceKey: String, sourceSize: Int64, destinationKey: String) {
            self.sourceKey = sourceKey
            self.sourceSize = sourceSize
            self.destinationKey = destinationKey
        }
    }

    public struct Plan: Sendable {
        public let upserts: [PlanEntry]
        /// Destination-side keys that exist in the destination but not in
        /// the source. Only populated for mirror jobs with
        /// `deletePropagation == true`.
        public let deletes: [String]

        public init(upserts: [PlanEntry], deletes: [String]) {
            self.upserts = upserts
            self.deletes = deletes
        }
    }

    /// Compute the set of upserts and (for mirror jobs with delete
    /// propagation) deletes. Pure function — same inputs, same plan.
    public static func makePlan(
        job: SyncJob,
        source: [S3Object],
        destination: [S3Object]
    ) -> Plan {
        let destIndex: [String: S3Object] = Dictionary(
            uniqueKeysWithValues: destination.map { ($0.key, $0) }
        )

        var upserts: [PlanEntry] = []
        for s in source where !s.isFolder {
            let relative = relativeKey(s.key, under: job.source.prefix)
            guard !relative.isEmpty else { continue }
            guard matches(relative, includes: job.includeGlobs, excludes: job.excludeGlobs) else {
                continue
            }
            let destKey = job.destination.prefix + relative
            if let existing = destIndex[destKey], isUnchanged(
                source: s, dest: existing, strategy: job.diffStrategy
            ) {
                continue
            }
            upserts.append(PlanEntry(
                sourceKey: s.key,
                sourceSize: s.size,
                destinationKey: destKey
            ))
        }

        var deletes: [String] = []
        if job.mode == .mirror && job.deletePropagation {
            // Destination-side keys whose corresponding relative path is
            // absent from the source. Filtered by the same include/exclude
            // globs as the upsert side so a mirror job for `*.jpg`
            // never deletes unrelated files in the destination.
            let sourceRelatives = Set(
                source
                    .filter { !$0.isFolder }
                    .map { relativeKey($0.key, under: job.source.prefix) }
            )
            for d in destination where !d.isFolder {
                let relative = relativeKey(d.key, under: job.destination.prefix)
                guard matches(relative, includes: job.includeGlobs, excludes: job.excludeGlobs) else {
                    continue
                }
                if !sourceRelatives.contains(relative) {
                    deletes.append(d.key)
                }
            }
        }

        return Plan(upserts: upserts, deletes: deletes)
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
