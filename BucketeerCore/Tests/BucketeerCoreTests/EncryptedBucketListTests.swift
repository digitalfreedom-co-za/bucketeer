//
//  EncryptedBucketListTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// The File Provider extension refuses buckets on this list. A missing
/// list must throw so the extension can fail closed.
@Suite("EncryptedBucketList")
struct EncryptedBucketListTests {

    @Test("Lists exactly the buckets that have a key")
    func listsEncryptedBuckets() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "EncryptedBuckets-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let key = BucketEncryptionKey(label: "Key", accountID: UUID(), bucket: "photos")

        try EncryptedBucketList.write([key], to: url)

        let encrypted = EncryptedBucketList.entry(accountID: key.accountID, bucket: "photos")
        let plain = EncryptedBucketList.entry(accountID: key.accountID, bucket: "photos-archive")
        #expect(try EncryptedBucketList.contains(domainIdentifier: encrypted, at: url))
        #expect(try !EncryptedBucketList.contains(domainIdentifier: plain, at: url))
    }

    @Test("A missing list throws instead of reporting no encryption")
    func missingListThrows() {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "EncryptedBuckets-\(UUID().uuidString).json")

        #expect(throws: (any Error).self) {
            try EncryptedBucketList.contains(domainIdentifier: "any::bucket", at: url)
        }
    }
}
