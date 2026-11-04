//
//  FinderChangeStateTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

@Suite("FinderChangeState")
struct FinderChangeStateTests {

    private func state(_ entries: [String: String], prefixes: [String] = []) -> FinderChangeState {
        var state = FinderChangeState(anchor: "a0")
        for prefix in prefixes { state.track(prefix: prefix) }
        _ = state.advance(to: entries, anchor: "a1")
        return state
    }

    @Test("New and changed keys are updates, missing keys are deletions")
    func diffReportsUpdatesAndDeletions() {
        var current = state(["a.txt": "1", "b.txt": "1", "c.txt": "1"])
        let diff = current.advance(to: ["a.txt": "1", "b.txt": "2", "d.txt": "1"], anchor: "a2")
        #expect(diff == ListingDiff(updated: ["b.txt", "d.txt"], deleted: ["c.txt"]))
    }

    @Test("ETags compare without quotes, so a re-quoted ETag is no change")
    func quotesAreNoChange() {
        var current = state(["a.txt": "\"1\""])
        let diff = current.advance(to: ["a.txt": "1"], anchor: "a2")
        #expect(diff == ListingDiff(updated: [], deleted: []))
    }

    @Test("Advancing moves the anchor")
    func advanceMovesAnchor() {
        var current = state([:])
        _ = current.advance(to: [:], anchor: "a2")
        #expect(current.anchor == "a2")
    }

    @Test("The bucket root is always tracked; other prefixes once")
    func trackingPrefixes() {
        var current = FinderChangeState(anchor: "a0")
        #expect(current.trackedPrefixes == [""])
        let first = current.track(prefix: "docs/")
        let second = current.track(prefix: "docs/")
        #expect(first)
        #expect(!second)
    }

    @Test("A folder that vanished from its tracked parent is no longer tracked")
    func vanishedFolderIsPruned() {
        var current = state(
            ["docs/": "", "docs/a.txt": "1", "docs/old/": "", "docs/old/x.txt": "1"],
            prefixes: ["docs/", "docs/old/"]
        )
        let diff = current.advance(to: ["docs/": "", "docs/a.txt": "1"], anchor: "a2")
        #expect(diff.deleted == ["docs/old/", "docs/old/x.txt"])
        #expect(current.trackedPrefixes == ["", "docs/"])
    }

    @Test("A listing of some prefixes neither deletes nor reports items of the others")
    func partialListingKeepsOtherPrefixes() {
        var current = state(["docs/": "", "top.txt": "1"])
        current.record(["docs/a.txt": "1"], under: "docs/")
        let diff = current.advance(to: ["docs/": "", "top.txt": "2"], listedPrefixes: [""], anchor: "a2")
        #expect(diff == ListingDiff(updated: ["top.txt"], deleted: []))
        #expect(current.entries["docs/a.txt"] == "1")
    }

    @Test("Recording delivered items bumps the revision and tracks the folder")
    func recordBumpsRevision() {
        var current = state([:])
        let before = current.revision
        current.record(["docs/a.txt": "\"1\""], under: "docs/")
        #expect(current.revision > before)
        #expect(current.trackedPrefixes.contains("docs/"))
        #expect(current.entries["docs/a.txt"] == "1")
    }

    @Test("The versions Finder knows below a folder include items handed back after a change, in open folders only")
    func knownVersionsBelowAFolder() {
        var current = state(["docs/": "", "top.txt": "1"])
        current.record(["docs/a.txt": "1", "docs/sub/": ""], under: "docs/")
        current.remember("docs/c.txt", etag: "\"2\"")
        current.remember("other/x.txt", etag: "3")
        #expect(current.knownVersions(under: "docs/") == ["docs/a.txt": "1", "docs/c.txt": "2"])
        #expect(current.entries["other/x.txt"] == nil)
    }
}

private extension FinderChangeState {
    /// A fresh listing of every tracked prefix.
    mutating func advance(to listing: [String: String], anchor: String) -> ListingDiff {
        advance(to: listing, listedPrefixes: trackedPrefixes, anchor: anchor)
    }
}

@Suite("ETag.matches")
struct ETagMatchTests {

    @Test("Same ETag with or without quotes matches")
    func sameETag() {
        #expect(ETag.matches(base: "\"abc\"", current: "abc"))
    }

    @Test("A different ETag does not match")
    func differentETag() {
        #expect(!ETag.matches(base: "abc", current: "def"))
    }

    @Test("A missing server object or an unknown base never matches")
    func missingSides() {
        #expect(!ETag.matches(base: "abc", current: nil))
        #expect(!ETag.matches(base: nil, current: "abc"))
        #expect(!ETag.matches(base: "", current: ""))
    }
}
