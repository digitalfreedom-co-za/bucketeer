//
//  MountedBucketTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// Finder changes reach the bucket only against the version Finder knew;
/// a newer or colliding server object is never overwritten or deleted,
/// and fetched bytes always belong to the version reported with them.
@Suite("MountedBucket")
struct MountedBucketTests {

    private let account = S3Account(name: "Test", provider: .awsS3)
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("MountedBucketTests-\(UUID().uuidString)", isDirectory: true)

    private func setUp() async throws -> (InMemoryS3Browser, MountedBucket) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let browser = InMemoryS3Browser()
        await browser.addBucket("b")
        let mounted = MountedBucket(browser: browser, account: account, bucket: "b",
                                    transport: InMemoryTransport(browser: browser, bucket: "b"))
        return (browser, mounted)
    }

    private func localFile(_ text: String) throws -> URL {
        let url = folder.appendingPathComponent(UUID().uuidString)
        try Data(text.utf8).write(to: url)
        return url
    }

    // MARK: - Create (F14)

    @Test("Creating a file whose name was taken meanwhile writes a conflict copy and keeps the original")
    func createCollisionMakesConflictCopy() async throws {
        let (browser, mounted) = try await setUp()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try await browser.write(bucket: "b", key: "notes.txt", data: Data("server".utf8), precondition: nil)

        let placement = try await mounted.create("notes.txt", contents: try localFile("finder"), mayAlreadyExist: false)

        #expect(placement.isConflict)
        #expect(placement.object.key.hasPrefix("notes (conflict "))
        #expect(await browser.data(bucket: "b", key: "notes.txt") == Data("server".utf8))
        #expect(await browser.data(bucket: "b", key: placement.object.key) == Data("finder".utf8))
    }

    @Test("Re-importing a file the bucket already holds unchanged reuses it")
    func reimportOfIdenticalFileReusesIt() async throws {
        let (browser, mounted) = try await setUp()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try await browser.write(bucket: "b", key: "notes.txt", data: Data("same".utf8), precondition: nil)

        let placement = try await mounted.create("notes.txt", contents: try localFile("same"), mayAlreadyExist: true)

        #expect(!placement.isConflict)
        #expect(placement.object.key == "notes.txt")
        #expect(await browser.storedKeys(in: "b") == ["notes.txt"])
    }

    // MARK: - Rename and delete (F15)

    @Test("Renaming onto an existing name never replaces it")
    func renameOntoExistingNameMakesConflictCopy() async throws {
        let (browser, mounted) = try await setUp()
        defer { try? FileManager.default.removeItem(at: folder) }
        let base = try await browser.write(bucket: "b", key: "draft.txt", data: Data("draft".utf8), precondition: nil)
        _ = try await browser.write(bucket: "b", key: "final.txt", data: Data("final".utf8), precondition: nil)

        let placement = try await mounted.rename("draft.txt", baseVersion: base, to: "final.txt")

        #expect(placement.isConflict)
        #expect(placement.object.key.hasPrefix("final (conflict "))
        #expect(await browser.data(bucket: "b", key: "final.txt") == Data("final".utf8))
        #expect(await browser.data(bucket: "b", key: placement.object.key) == Data("draft".utf8))
        #expect(await browser.data(bucket: "b", key: "draft.txt") == nil)
    }

    @Test("A rename based on an outdated version leaves the newer server object where it is")
    func renameOfChangedObjectIsRefused() async throws {
        let (browser, mounted) = try await setUp()
        defer { try? FileManager.default.removeItem(at: folder) }
        let base = try await browser.write(bucket: "b", key: "draft.txt", data: Data("v1".utf8), precondition: nil)
        _ = try await browser.write(bucket: "b", key: "draft.txt", data: Data("v2".utf8), precondition: nil)

        let placement = try await mounted.rename("draft.txt", baseVersion: base, to: "final.txt")

        #expect(placement.isConflict)
        #expect(placement.object.key == "draft.txt")
        #expect(await browser.storedKeys(in: "b") == ["draft.txt"])
    }

    @Test("A delete based on an outdated version is refused and keeps the newer object")
    func deleteOfChangedObjectIsRefused() async throws {
        let (browser, mounted) = try await setUp()
        defer { try? FileManager.default.removeItem(at: folder) }
        let base = try await browser.write(bucket: "b", key: "draft.txt", data: Data("v1".utf8), precondition: nil)
        _ = try await browser.write(bucket: "b", key: "draft.txt", data: Data("v2".utf8), precondition: nil)

        await #expect(throws: MountedBucket.Refusal.changedOnServer) {
            try await mounted.delete("draft.txt", baseVersion: base)
        }

        #expect(await browser.data(bucket: "b", key: "draft.txt") == Data("v2".utf8))
    }

    // MARK: - Fetch (F16)

    @Test("A fetch for a version the server no longer has is refused; other fetches read the reported version")
    func fetchIsBoundToTheReportedVersion() async throws {
        let (browser, mounted) = try await setUp()
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = try await browser.write(bucket: "b", key: "draft.txt", data: Data("v1".utf8), precondition: nil)
        let current = try await browser.write(bucket: "b", key: "draft.txt", data: Data("v2".utf8), precondition: nil)
        let target = folder.appendingPathComponent("fetched")

        await #expect(throws: MountedBucket.Refusal.versionUnavailable) {
            _ = try await mounted.fetch("draft.txt", requestedVersion: old, to: target)
        }
        let fetched = try await mounted.fetch("draft.txt", requestedVersion: nil, to: target)

        #expect(fetched.etag == current)
        #expect(try Data(contentsOf: target) == Data("v2".utf8))
    }
}

/// Transport on top of the in-memory bucket: uploads honour their
/// precondition, downloads only succeed for the requested ETag.
private struct InMemoryTransport: MountedContentTransport {
    let browser: InMemoryS3Browser
    let bucket: String

    func upload(_ url: URL, to key: String, precondition: WritePrecondition?) async throws -> String? {
        try await browser.write(bucket: bucket, key: key, data: Data(contentsOf: url), precondition: precondition)
    }

    func download(_ key: String, matching etag: String, size: Int64, to url: URL) async throws {
        let current = try await browser.head(account: S3Account(name: "", provider: .awsS3), bucket: bucket, key: key)
        guard ETag.matches(base: etag, current: current.etag), let data = await browser.data(bucket: bucket, key: key) else {
            throw BucketeerError.preconditionFailed(key: key)
        }
        try data.write(to: url)
    }
}
