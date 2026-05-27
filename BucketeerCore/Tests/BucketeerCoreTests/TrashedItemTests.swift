//
//  TrashedItemTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import Testing
@testable import BucketeerCore

@Suite("TrashedItem.displayName")
struct TrashedItemTests {

    private func make(key: String) -> TrashedItem {
        TrashedItem(
            accountID: UUID(),
            accountName: "n",
            bucket: "b",
            key: key,
            size: 0,
            contentType: nil,
            etag: nil,
            expiresAt: Date()
        )
    }

    @Test("Strips parent path of multi-segment key")
    func multiSegment() {
        #expect(make(key: "a/b/c/file.txt").displayName == "file.txt")
    }

    @Test("Single-segment key is returned verbatim")
    func singleSegment() {
        #expect(make(key: "file.txt").displayName == "file.txt")
    }

    @Test("Empty key returns empty")
    func emptyKey() {
        #expect(make(key: "").displayName == "")
    }

    @Test("Trailing slash key returns empty (folder-style)")
    func trailingSlash() {
        #expect(make(key: "folder/").displayName == "")
    }
}
