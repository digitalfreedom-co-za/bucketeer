//
//  FinderWriteAccessTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 05.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

@Suite("Finder write access")
struct FinderWriteAccessTests {

    private func withAccess(_ body: (FinderWriteAccess, String) -> Void) {
        let suiteName = "FinderWriteAccessTests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        body(FinderWriteAccess(suiteName: suiteName), suiteName)
    }

    @Test("Mounts stay writable until the host has decided")
    func writableBeforeTheHostDecides() {
        withAccess { access, _ in
            #expect(access.allowsWrites(at: Date()))
        }
    }

    @Test("A trial grant ends on its own, even while the host is not running")
    func trialGrantEndsWithoutTheHost() {
        withAccess { access, suiteName in
            let trialEnd = Date(timeIntervalSince1970: 1_800_000_000)
            access.allowWrites(until: trialEnd)

            let extensionSide = FinderWriteAccess(suiteName: suiteName)
            #expect(extensionSide.allowsWrites(at: trialEnd.addingTimeInterval(-1)))
            #expect(!extensionSide.allowsWrites(at: trialEnd))
        }
    }

    @Test("A lapsed entitlement locks at once, a restored one unlocks")
    func followsTheHostDecision() {
        withAccess { access, suiteName in
            let now = Date()
            access.allowWrites(until: .distantPast)
            #expect(!FinderWriteAccess(suiteName: suiteName).allowsWrites(at: now))
            access.allowWrites(until: .distantFuture)
            #expect(FinderWriteAccess(suiteName: suiteName).allowsWrites(at: now))
        }
    }
}
