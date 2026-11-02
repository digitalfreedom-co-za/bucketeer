//
//  OpenWithRoundTripTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

@Suite("ConflictCopyName")
struct ConflictCopyNameTests {

    private let date = Date(timeIntervalSince1970: 1_793_621_133) // 2026-11-02 12:05:33 UTC
    private let utc = TimeZone(identifier: "UTC")!

    @Test("Inserts the conflict marker before the extension")
    func keepsExtension() {
        #expect(ConflictCopyName.key(for: "docs/report.pdf", date: date, timeZone: utc)
                == "docs/report (conflict 2026-11-02 12.05.33).pdf")
    }

    @Test("Names without an extension get the marker at the end")
    func noExtension() {
        #expect(ConflictCopyName.key(for: "README", date: date, timeZone: utc)
                == "README (conflict 2026-11-02 12.05.33)")
    }

    @Test("Hidden files keep their leading dot as part of the name")
    func hiddenFile() {
        #expect(ConflictCopyName.key(for: "config/.env", date: date, timeZone: utc)
                == "config/.env (conflict 2026-11-02 12.05.33)")
    }

    @Test("Only the last extension is split off")
    func doubleExtension() {
        #expect(ConflictCopyName.key(for: "backup.tar.gz", date: date, timeZone: utc)
                == "backup.tar (conflict 2026-11-02 12.05.33).gz")
    }

    @Test("Dots in folder names are not taken for an extension")
    func dottedFolder() {
        #expect(ConflictCopyName.key(for: "v1.2/notes", date: date, timeZone: utc)
                == "v1.2/notes (conflict 2026-11-02 12.05.33)")
    }
}

@Suite("OpenWithRoundTrip")
struct OpenWithRoundTripTests {

    /// Server double: one ETag per key, bumped on every upload.
    actor FakeRemote: OpenWithRemote {
        private(set) var etags: [String: String] = [:]
        private(set) var uploads: [(key: String, ifMatch: String?)] = []
        /// Answer 412 on the next conditional upload even though HEAD
        /// matched (someone wrote between our HEAD and our PUT).
        var failNextConditionalUpload = false
        private var counter = 0

        init(etags: [String: String]) { self.etags = etags }

        func setETag(_ etag: String?, for key: String) { etags[key] = etag }
        func failNextConditional() { failNextConditionalUpload = true }

        func currentETag(of object: RemoteObjectRef) async throws -> String? {
            etags[object.key]
        }

        func upload(_ localURL: URL, to object: RemoteObjectRef, ifMatch: String?) async throws -> ConditionalUploadResult {
            if let ifMatch {
                if failNextConditionalUpload || etags[object.key] != ifMatch {
                    failNextConditionalUpload = false
                    return .preconditionFailed
                }
            }
            uploads.append((object.key, ifMatch))
            counter += 1
            etags[object.key] = "etag-\(counter)"
            return .uploaded
        }
    }

    private let accountID = UUID()
    private let date = Date(timeIntervalSince1970: 1_793_621_133)

    private func makeFile(_ contents: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenWithRoundTripTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("report.txt")
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func object(_ key: String = "docs/report.txt") -> RemoteObjectRef {
        RemoteObjectRef(accountID: accountID, bucket: "bucket", key: key)
    }

    private func roundTrip(_ remote: FakeRemote) -> OpenWithRoundTrip {
        OpenWithRoundTrip(remote: remote, now: { [date] in date }, timeZone: TimeZone(identifier: "UTC")!)
    }

    @Test("An untouched file is not uploaded")
    func unchangedFileSkipsUpload() async throws {
        let remote = FakeRemote(etags: ["docs/report.txt": "base"])
        let trip = roundTrip(remote)
        let file = try makeFile("v1")
        try await trip.register(localURL: file, object: object(), etag: "base")

        #expect(try await trip.syncChanges(at: file) == .unchanged)
        #expect(await remote.uploads.isEmpty)
    }

    @Test("A saved file goes up with If-Match on the downloaded ETag")
    func savedFileUploadsConditionally() async throws {
        let remote = FakeRemote(etags: ["docs/report.txt": "base"])
        let trip = roundTrip(remote)
        let file = try makeFile("v1")
        try await trip.register(localURL: file, object: object(), etag: "base")

        try Data("v2".utf8).write(to: file)
        #expect(try await trip.syncChanges(at: file) == .uploaded(key: "docs/report.txt"))
        #expect(await remote.uploads.map(\.ifMatch) == ["base"])
    }

    @Test("The next save uses the ETag of our own upload")
    func secondSaveUsesNewETag() async throws {
        let remote = FakeRemote(etags: ["docs/report.txt": "base"])
        let trip = roundTrip(remote)
        let file = try makeFile("v1")
        try await trip.register(localURL: file, object: object(), etag: "base")

        try Data("v2".utf8).write(to: file)
        _ = try await trip.syncChanges(at: file)
        try Data("v3".utf8).write(to: file)
        #expect(try await trip.syncChanges(at: file) == .uploaded(key: "docs/report.txt"))
        #expect(await remote.uploads.map(\.ifMatch) == ["base", "etag-1"])
    }

    @Test("A server-side change leads to a conflict copy, the original stays")
    func remoteChangeCreatesConflictCopy() async throws {
        let remote = FakeRemote(etags: ["docs/report.txt": "base"])
        let trip = roundTrip(remote)
        let file = try makeFile("v1")
        try await trip.register(localURL: file, object: object(), etag: "base")

        await remote.setETag("someone-else", for: "docs/report.txt")
        try Data("mine".utf8).write(to: file)

        let copy = "docs/report (conflict 2026-11-02 12.05.33).txt"
        #expect(try await trip.syncChanges(at: file) == .conflict(copyKey: copy))
        #expect(await remote.etags["docs/report.txt"] == "someone-else")
        #expect(await remote.uploads.map(\.key) == [copy])
    }

    @Test("A 412 on upload is handled like a server-side change")
    func preconditionFailureCreatesConflictCopy() async throws {
        let remote = FakeRemote(etags: ["docs/report.txt": "base"])
        let trip = roundTrip(remote)
        let file = try makeFile("v1")
        try await trip.register(localURL: file, object: object(), etag: "base")

        await remote.failNextConditional()
        try Data("mine".utf8).write(to: file)

        #expect(try await trip.syncChanges(at: file)
                == .conflict(copyKey: "docs/report (conflict 2026-11-02 12.05.33).txt"))
    }

    @Test("A deleted object is not silently recreated")
    func deletedObjectCreatesConflictCopy() async throws {
        let remote = FakeRemote(etags: ["docs/report.txt": "base"])
        let trip = roundTrip(remote)
        let file = try makeFile("v1")
        try await trip.register(localURL: file, object: object(), etag: "base")

        await remote.setETag(nil, for: "docs/report.txt")
        try Data("mine".utf8).write(to: file)

        #expect(try await trip.syncChanges(at: file)
                == .conflict(copyKey: "docs/report (conflict 2026-11-02 12.05.33).txt"))
        #expect(await remote.etags["docs/report.txt"] == nil)
    }

    @Test("After a conflict, further saves update the conflict copy")
    func savesAfterConflictFollowTheCopy() async throws {
        let remote = FakeRemote(etags: ["docs/report.txt": "base"])
        let trip = roundTrip(remote)
        let file = try makeFile("v1")
        try await trip.register(localURL: file, object: object(), etag: "base")

        await remote.setETag("someone-else", for: "docs/report.txt")
        try Data("mine".utf8).write(to: file)
        _ = try await trip.syncChanges(at: file)

        try Data("mine again".utf8).write(to: file)
        let copy = "docs/report (conflict 2026-11-02 12.05.33).txt"
        #expect(try await trip.syncChanges(at: file) == .uploaded(key: copy))
        #expect(await remote.uploads.map(\.ifMatch) == [nil, "etag-1"])
        #expect(await remote.etags["docs/report.txt"] == "someone-else")
    }

    @Test("Files that were never registered are ignored")
    func unknownFileIgnored() async throws {
        let remote = FakeRemote(etags: [:])
        let trip = roundTrip(remote)
        let file = try makeFile("v1")
        #expect(try await trip.syncChanges(at: file) == .unchanged)
    }

    @Test("ETags compare and travel without surrounding quotes")
    func quotedETagsMatch() async throws {
        let remote = FakeRemote(etags: ["docs/report.txt": "base"])
        let trip = roundTrip(remote)
        let file = try makeFile("v1")
        try await trip.register(localURL: file, object: object(), etag: "\"base\"")

        try Data("v2".utf8).write(to: file)
        #expect(try await trip.syncChanges(at: file) == .uploaded(key: "docs/report.txt"))
        #expect(await remote.uploads.map(\.ifMatch) == ["base"])
    }
}
