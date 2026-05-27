//
//  SyncPlannerTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import Testing
@testable import BucketeerCore

@Suite("SyncPlanner")
struct SyncPlannerTests {

    // MARK: - Fixtures

    private let sourceAccountID = UUID()
    private let destAccountID = UUID()

    private func endpoint(prefix: String, accountID: UUID? = nil) -> SyncEndpoint {
        .s3(
            accountID: accountID ?? sourceAccountID,
            bucket: "bucket",
            prefix: prefix
        )
    }

    private func localEndpoint(at displayPath: String = "/tmp/sync-local") -> SyncEndpoint {
        // Bookmark data is opaque to the planner — it just routes off
        // the case discriminator, so an empty Data is fine here.
        .localFolder(bookmark: Data(), displayPath: displayPath)
    }

    private func job(
        mode: SyncMode = .copy,
        sourcePrefix: String = "",
        destPrefix: String = "",
        diffStrategy: SyncDiffStrategy = .nameAndSize,
        includeGlobs: [String] = [],
        excludeGlobs: [String] = [],
        deletePropagation: Bool = false,
        source: SyncEndpoint? = nil,
        destination: SyncEndpoint? = nil
    ) -> SyncJob {
        SyncJob(
            name: "test",
            mode: mode,
            source: source ?? endpoint(prefix: sourcePrefix, accountID: sourceAccountID),
            destination: destination ?? endpoint(prefix: destPrefix, accountID: destAccountID),
            diffStrategy: diffStrategy,
            includeGlobs: includeGlobs,
            excludeGlobs: excludeGlobs,
            deletePropagation: deletePropagation
        )
    }

    private func object(_ key: String, size: Int64 = 100, etag: String = "etag") -> S3Object {
        S3Object(
            key: key,
            size: size,
            lastModified: Date(timeIntervalSince1970: 0),
            etag: etag
        )
    }

    // MARK: - Plan core

    @Test("Empty source → no upserts and no deletes")
    func emptySource() {
        let plan = SyncPlanner.makePlan(job: job(), source: [], destination: [])
        #expect(plan.upserts.isEmpty)
        #expect(plan.deletes.isEmpty)
    }

    @Test("Every new source object becomes an upsert when destination is empty")
    func allNewUpserts() {
        let plan = SyncPlanner.makePlan(
            job: job(),
            source: [object("a.txt"), object("b.txt")],
            destination: []
        )
        #expect(plan.upserts.map(\.sourceKey) == ["a.txt", "b.txt"])
        #expect(plan.upserts.map(\.destinationKey) == ["a.txt", "b.txt"])
    }

    @Test("Unchanged objects skipped under nameAndSize strategy")
    func unchangedSkippedBySize() {
        let plan = SyncPlanner.makePlan(
            job: job(diffStrategy: .nameAndSize),
            source: [object("a.txt", size: 100)],
            destination: [object("a.txt", size: 100, etag: "different")]
        )
        #expect(plan.upserts.isEmpty)
    }

    @Test("Size mismatch triggers an upsert")
    func sizeMismatchTriggersUpsert() {
        let plan = SyncPlanner.makePlan(
            job: job(diffStrategy: .nameAndSize),
            source: [object("a.txt", size: 200)],
            destination: [object("a.txt", size: 100)]
        )
        #expect(plan.upserts.count == 1)
        #expect(plan.upserts[0].sourceKey == "a.txt")
    }

    @Test("nameAndEtag strategy requires non-empty ETag to skip")
    func etagStrategyRequiresEtag() {
        // Same name+size, same etag → skip
        let skipped = SyncPlanner.makePlan(
            job: job(diffStrategy: .nameAndEtag),
            source: [object("a", etag: "x")],
            destination: [object("a", etag: "x")]
        )
        #expect(skipped.upserts.isEmpty)

        // Same name+size but different etag → upsert
        let differs = SyncPlanner.makePlan(
            job: job(diffStrategy: .nameAndEtag),
            source: [object("a", etag: "x")],
            destination: [object("a", etag: "y")]
        )
        #expect(differs.upserts.count == 1)

        // Empty source etag — strategy must fall through to "changed"
        // (we can't trust an empty etag to mean equivalence).
        let emptyEtag = SyncPlanner.makePlan(
            job: job(diffStrategy: .nameAndEtag),
            source: [object("a", etag: "")],
            destination: [object("a", etag: "x")]
        )
        #expect(emptyEtag.upserts.count == 1)
    }

    // MARK: - Prefix relocation

    @Test("Destination prefix is prepended to relative source key")
    func prefixRelocation() {
        let plan = SyncPlanner.makePlan(
            job: job(sourcePrefix: "src/", destPrefix: "dst/"),
            source: [object("src/a.txt"), object("src/sub/b.txt")],
            destination: []
        )
        #expect(plan.upserts.map(\.destinationKey) == ["dst/a.txt", "dst/sub/b.txt"])
    }

    @Test("Source objects equal to the prefix itself are skipped (empty relative key)")
    func emptyRelativeIsSkipped() {
        let plan = SyncPlanner.makePlan(
            job: job(sourcePrefix: "src/"),
            source: [object("src/")],
            destination: []
        )
        #expect(plan.upserts.isEmpty)
    }

    // MARK: - Globs

    @Test("Include glob keeps only matching files")
    func includeGlobFilters() {
        let plan = SyncPlanner.makePlan(
            job: job(includeGlobs: ["*.jpg"]),
            source: [object("a.jpg"), object("b.png"), object("c.JPG")],
            destination: []
        )
        // LIKE is case-sensitive by default — only lowercase .jpg matches
        #expect(plan.upserts.map(\.sourceKey) == ["a.jpg"])
    }

    @Test("Exclude glob removes matching files even when include matches")
    func excludeGlobOverridesInclude() {
        let plan = SyncPlanner.makePlan(
            job: job(includeGlobs: ["*"], excludeGlobs: ["*.tmp"]),
            source: [object("keep.txt"), object("drop.tmp")],
            destination: []
        )
        #expect(plan.upserts.map(\.sourceKey) == ["keep.txt"])
    }

    @Test("? matches a single character per the LIKE convention")
    func questionMarkPattern() {
        #expect(SyncPlanner.glob("abc.txt", matches: "a?c.txt") == true)
        #expect(SyncPlanner.glob("abbbbc.txt", matches: "a?c.txt") == false)
    }

    // MARK: - Mirror deletes

    @Test("Mirror without deletePropagation never emits deletes")
    func mirrorWithoutDeletePropDoesNotDelete() {
        let plan = SyncPlanner.makePlan(
            job: job(mode: .mirror, deletePropagation: false),
            source: [],
            destination: [object("orphan.txt")]
        )
        #expect(plan.deletes.isEmpty)
    }

    @Test("Mirror with deletePropagation emits destination-only orphans")
    func mirrorDeletesOrphans() {
        let plan = SyncPlanner.makePlan(
            job: job(mode: .mirror, deletePropagation: true),
            source: [object("keep.txt")],
            destination: [object("keep.txt"), object("orphan.txt")]
        )
        #expect(plan.deletes == ["orphan.txt"])
    }

    @Test("Mirror deletes respect exclude globs — Codex review #6 regression test")
    func mirrorDeletesRespectExcludes() {
        let plan = SyncPlanner.makePlan(
            job: job(mode: .mirror, excludeGlobs: ["*.log"], deletePropagation: true),
            source: [],
            destination: [object("orphan.txt"), object("noise.log")]
        )
        // *.log is excluded from both upsert and delete consideration
        #expect(plan.deletes == ["orphan.txt"])
    }

    @Test("Mirror deletes respect include globs")
    func mirrorDeletesRespectIncludes() {
        let plan = SyncPlanner.makePlan(
            job: job(mode: .mirror, includeGlobs: ["*.jpg"], deletePropagation: true),
            source: [],
            destination: [object("orphan.jpg"), object("orphan.txt")]
        )
        // Only files matching the include glob are eligible for deletion
        #expect(plan.deletes == ["orphan.jpg"])
    }

    // MARK: - relativeKey helper

    @Test("relativeKey strips the source prefix")
    func relativeKeyStrips() {
        #expect(SyncPlanner.relativeKey("src/a/b.txt", under: "src/") == "a/b.txt")
        #expect(SyncPlanner.relativeKey("src/a/b.txt", under: "") == "src/a/b.txt")
        #expect(SyncPlanner.relativeKey("other/x", under: "src/") == "other/x")
    }

    // MARK: - Phase 9.8 — local-folder endpoint coverage

    @Test("prefix(for:) returns empty for local folders, S3 prefix for s3")
    func prefixForEndpoint() {
        let local = SyncEndpoint.localFolder(bookmark: Data(), displayPath: "/x")
        #expect(SyncPlanner.prefix(for: local) == "")
        let s3 = SyncEndpoint.s3(accountID: UUID(), bucket: "b", prefix: "p/")
        #expect(SyncPlanner.prefix(for: s3) == "p/")
    }

    @Test("Local → S3: keys land under destination prefix")
    func localToS3UsesDestPrefix() {
        let job = self.job(
            destPrefix: "dst/",
            source: localEndpoint(),
            destination: endpoint(prefix: "dst/", accountID: destAccountID)
        )
        let plan = SyncPlanner.makePlan(
            job: job,
            source: [object("a.txt"), object("subdir/b.txt")],
            destination: []
        )
        #expect(plan.upserts.map(\.destinationKey) == ["dst/a.txt", "dst/subdir/b.txt"])
    }

    @Test("S3 → Local: source prefix is stripped, destination has no prefix")
    func s3ToLocalStripsPrefix() {
        let job = self.job(
            sourcePrefix: "src/",
            source: endpoint(prefix: "src/", accountID: sourceAccountID),
            destination: localEndpoint()
        )
        let plan = SyncPlanner.makePlan(
            job: job,
            source: [object("src/a.txt"), object("src/sub/b.txt")],
            destination: []
        )
        // Destination is local — relative key only, no prefix applied
        #expect(plan.upserts.map(\.destinationKey) == ["a.txt", "sub/b.txt"])
    }

    @Test("Local → Local: pure relative-key copy without prefixes")
    func localToLocal() {
        let job = self.job(
            source: localEndpoint(at: "/src"),
            destination: localEndpoint(at: "/dst")
        )
        let plan = SyncPlanner.makePlan(
            job: job,
            source: [object("photo.jpg")],
            destination: []
        )
        #expect(plan.upserts.count == 1)
        #expect(plan.upserts[0].sourceKey == "photo.jpg")
        #expect(plan.upserts[0].destinationKey == "photo.jpg")
    }

    @Test("Local mirror with deletePropagation orphans destination-only files")
    func localMirrorDeletes() {
        let job = self.job(
            mode: .mirror,
            deletePropagation: true,
            source: localEndpoint(),
            destination: localEndpoint(at: "/other")
        )
        let plan = SyncPlanner.makePlan(
            job: job,
            source: [object("keep.txt")],
            destination: [object("keep.txt"), object("orphan.txt")]
        )
        #expect(plan.deletes == ["orphan.txt"])
    }
}
