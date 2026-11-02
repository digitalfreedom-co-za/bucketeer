//
//  LocalFolderEnumeratorTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// A missing source folder must not look like an empty one: a mirror
/// job with delete propagation would then delete every destination key.
@Suite("LocalFolderEnumerator")
struct LocalFolderEnumeratorTests {

    @Test("A missing root throws instead of returning an empty listing")
    func missingRootThrows() {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "LocalFolderEnumeratorTests-missing-\(UUID().uuidString)")
        #expect(throws: BucketeerError.self) {
            _ = try LocalFolderEnumerator.enumerate(at: missing)
        }
    }

    @Test("An existing folder lists its files with relative keys")
    func existingRootLists() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "LocalFolderEnumeratorTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "sub"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: root.appending(path: "sub/a.txt"))

        let objects = try LocalFolderEnumerator.enumerate(at: root)

        #expect(objects.map(\.key) == ["sub/a.txt"])
    }
}
