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

    @Test("Mounts stay writable until the host has decided, and follow it after")
    func followsTheHostDecision() {
        let suiteName = "FinderWriteAccessTests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let access = FinderWriteAccess(suiteName: suiteName)

        #expect(!access.isReadOnly)
        access.setReadOnly(true)
        #expect(FinderWriteAccess(suiteName: suiteName).isReadOnly)
        access.setReadOnly(false)
        #expect(!FinderWriteAccess(suiteName: suiteName).isReadOnly)
    }
}
