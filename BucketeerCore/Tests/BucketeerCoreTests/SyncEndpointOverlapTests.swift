//
//  SyncEndpointOverlapTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// A job whose source and destination contain each other copies into
/// itself or mirror-deletes its own source.
@Suite("SyncEndpointOverlap")
struct SyncEndpointOverlapTests {

    private let account = UUID()

    private func s3(_ prefix: String, bucket: String = "b", account: UUID? = nil) -> SyncEndpoint {
        .s3(accountID: account ?? self.account, bucket: bucket, prefix: prefix)
    }

    private let local = SyncEndpoint.localFolder(bookmark: Data(), displayPath: "")

    @Test("Prefixes in the same bucket overlap when one contains the other",
          arguments: [("", "photos/"), ("photos/", "photos/2026/"), ("photos", "photos-raw/"), ("a/", "a/")])
    func nestedPrefixesOverlap(first: String, second: String) {
        #expect(throws: BucketeerError.self) {
            try SyncEndpointOverlap.validate(source: s3(first), destination: s3(second))
        }
        #expect(throws: BucketeerError.self) {
            try SyncEndpointOverlap.validate(source: s3(second), destination: s3(first))
        }
    }

    @Test("Sibling prefixes, other buckets and other accounts are independent")
    func separateScopesAreAccepted() throws {
        try SyncEndpointOverlap.validate(source: s3("a/"), destination: s3("b/"))
        try SyncEndpointOverlap.validate(source: s3("a/"), destination: s3("a/", bucket: "other"))
        try SyncEndpointOverlap.validate(source: s3("a/"), destination: s3("a/", account: UUID()))
    }

    @Test("Local folders overlap after resolving symlinks, and siblings do not")
    func localFoldersAreComparedResolved() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncEndpointOverlapTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = root.appendingPathComponent("Photos", isDirectory: true)
        let child = parent.appendingPathComponent("2026", isDirectory: true)
        let sibling = root.appendingPathComponent("Photos Backup", isDirectory: true)
        let link = root.appendingPathComponent("shortcut", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: child)

        #expect(throws: BucketeerError.self) {
            try SyncEndpointOverlap.validate(source: local, destination: local, sourceRoot: parent, destinationRoot: link)
        }
        #expect(throws: BucketeerError.self) {
            try SyncEndpointOverlap.validate(source: local, destination: local, sourceRoot: link, destinationRoot: parent)
        }
        try SyncEndpointOverlap.validate(source: local, destination: local, sourceRoot: parent, destinationRoot: sibling)
    }
}
