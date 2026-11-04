//
//  VersionedDeleteTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// A move deletes its source only while the source is still the
/// version that was copied; a newer edit is kept.
@Suite("Versioned delete")
struct VersionedDeleteTests {

    private let account = S3Account(name: "Test", provider: .awsS3)

    @Test("An object still at the copied version is deleted")
    func unchangedObjectIsDeleted() async throws {
        let browser = InMemoryS3Browser()
        await browser.put(bucket: "b", key: "a.txt")
        let copied = try await browser.head(account: account, bucket: "b", key: "a.txt")

        let deleted = try await browser.deleteIfUnchanged(account: account, bucket: "b", key: "a.txt", etag: copied.etag)

        #expect(deleted)
        await #expect(throws: BucketeerError.self) {
            _ = try await browser.head(account: account, bucket: "b", key: "a.txt")
        }
    }

    @Test("An object rewritten after the copy is kept")
    func rewrittenObjectIsKept() async throws {
        let browser = InMemoryS3Browser()
        await browser.put(bucket: "b", key: "a.txt")
        let copied = try await browser.head(account: account, bucket: "b", key: "a.txt")
        await browser.rewrite(bucket: "b", key: "a.txt")

        let deleted = try await browser.deleteIfUnchanged(account: account, bucket: "b", key: "a.txt", etag: copied.etag)

        #expect(!deleted)
        #expect(try await browser.head(account: account, bucket: "b", key: "a.txt").etag != copied.etag)
    }

    @Test("A local file edited after it was listed is kept")
    func editedLocalFileIsKept() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VersionedDeleteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let edited = root.appendingPathComponent("edited.txt")
        let untouched = root.appendingPathComponent("untouched.txt")
        try Data("AAAA".utf8).write(to: edited)
        try Data("AAAA".utf8).write(to: untouched)
        let listed = try LocalFolderEnumerator.enumerate(at: root)
        let fingerprint = { (key: String) in LocalFileFingerprint(listed.first { $0.key == key }!) }
        try Data("BBBB".utf8).write(to: edited)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: edited.path)

        #expect(try !LocalFolderWriter.deleteIfUnchanged(relativeKey: "edited.txt", under: root, fingerprint: fingerprint("edited.txt")))
        #expect(try LocalFolderWriter.deleteIfUnchanged(relativeKey: "untouched.txt", under: root, fingerprint: fingerprint("untouched.txt")))
        #expect(FileManager.default.fileExists(atPath: edited.path))
        #expect(!FileManager.default.fileExists(atPath: untouched.path))
    }
}
