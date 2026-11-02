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
        #expect(ConflictCopyName.key(for: "docs/report.pdf", date: date, timeZone: utc, tag: "a1b2c3")
                == "docs/report (conflict 2026-11-02 12.05.33 a1b2c3).pdf")
    }

    @Test("Names without an extension get the marker at the end")
    func noExtension() {
        #expect(ConflictCopyName.key(for: "README", date: date, timeZone: utc, tag: "a1b2c3")
                == "README (conflict 2026-11-02 12.05.33 a1b2c3)")
    }

    @Test("Hidden files keep their leading dot as part of the name")
    func hiddenFile() {
        #expect(ConflictCopyName.key(for: "config/.env", date: date, timeZone: utc, tag: "a1b2c3")
                == "config/.env (conflict 2026-11-02 12.05.33 a1b2c3)")
    }

    @Test("Only the last extension is split off")
    func doubleExtension() {
        #expect(ConflictCopyName.key(for: "backup.tar.gz", date: date, timeZone: utc, tag: "a1b2c3")
                == "backup.tar (conflict 2026-11-02 12.05.33 a1b2c3).gz")
    }

    @Test("Dots in folder names are not taken for an extension")
    func dottedFolder() {
        #expect(ConflictCopyName.key(for: "v1.2/notes", date: date, timeZone: utc, tag: "a1b2c3")
                == "v1.2/notes (conflict 2026-11-02 12.05.33 a1b2c3)")
    }

    @Test("Random tags differ between calls")
    func randomTagsDiffer() {
        let tags = Set((0..<50).map { _ in ConflictCopyName.randomTag() })
        #expect(tags.count == 50)
        #expect(tags.allSatisfy { $0.count == 6 })
    }

    @Test("A taken name is retried with a fresh tag, never overwritten")
    func takenNameRetries() async throws {
        let tags = TagSequence(["aaaaaa", "aaaaaa", "bbbbbb"])
        let taken: Set<String> = ["docs/report (conflict 2026-11-02 12.05.33 aaaaaa).txt"]
        let created = try await ConflictCopyName.create(
            copyOf: "docs/report.txt",
            date: date,
            timeZone: utc,
            tag: { tags.next() }
        ) { key in taken.contains(key) ? nil : "etag-\(key.count)" }
        #expect(created.key == "docs/report (conflict 2026-11-02 12.05.33 bbbbbb).txt")
    }

    @Test("Gives up after a bounded number of taken names")
    func givesUp() async throws {
        await #expect(throws: BucketeerError.self) {
            _ = try await ConflictCopyName.create(
                copyOf: "docs/report.txt",
                date: date,
                timeZone: utc,
                tag: { "aaaaaa" }
            ) { _ -> String? in nil }
        }
    }
}

/// Hands out tags in order, then repeats the last one.
final class TagSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var tags: [String]

    init(_ tags: [String]) { self.tags = tags }

    func next() -> String {
        lock.withLock { tags.count > 1 ? tags.removeFirst() : tags[0] }
    }
}

@Suite("OpenWithRoundTrip")
struct OpenWithRoundTripTests {

    /// Server double: one ETag per key, bumped on every upload.
    actor FakeRemote: OpenWithRemote {
        private(set) var etags: [String: String] = [:]
        private(set) var uploads: [(key: String, precondition: WritePrecondition)] = []
        /// Answer 412 on the next conditional upload even though HEAD
        /// matched (someone wrote between our HEAD and our PUT).
        var failNextConditionalUpload = false
        /// Another client writes right after our next upload completes,
        /// before any HEAD we might send.
        var foreignWriteAfterNextUpload: String?
        private var counter = 0

        init(etags: [String: String]) { self.etags = etags }

        func setETag(_ etag: String?, for key: String) { etags[key] = etag }
        func failNextConditional() { failNextConditionalUpload = true }
        func writeAfterNextUpload(_ etag: String) { foreignWriteAfterNextUpload = etag }

        func currentETag(of object: RemoteObjectRef) async throws -> String? {
            etags[object.key]
        }

        func upload(
            _ localURL: URL,
            to object: RemoteObjectRef,
            precondition: WritePrecondition
        ) async throws -> ConditionalUploadResult {
            switch precondition {
            case .ifMatch(let base):
                if failNextConditionalUpload || etags[object.key] != base {
                    failNextConditionalUpload = false
                    return .preconditionFailed
                }
            case .ifAbsent:
                if etags[object.key] != nil { return .preconditionFailed }
            }
            uploads.append((object.key, precondition))
            counter += 1
            let written = "etag-\(counter)"
            etags[object.key] = written
            if let foreign = foreignWriteAfterNextUpload {
                foreignWriteAfterNextUpload = nil
                etags[object.key] = foreign
            }
            return .uploaded(etag: written)
        }
    }

    private let accountID = UUID()
    private let date = Date(timeIntervalSince1970: 1_793_621_133)
    private let copyKey = "docs/report (conflict 2026-11-02 12.05.33 aaaaaa).txt"

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

    private func roundTrip(_ remote: FakeRemote, tags: TagSequence = TagSequence(["aaaaaa"])) -> OpenWithRoundTrip {
        OpenWithRoundTrip(
            remote: remote,
            now: { [date] in date },
            timeZone: TimeZone(identifier: "UTC")!,
            tag: { tags.next() }
        )
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
        #expect(await remote.uploads.map(\.precondition) == [.ifMatch("base")])
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
        #expect(await remote.uploads.map(\.precondition) == [.ifMatch("base"), .ifMatch("etag-1")])
    }

    @Test("A foreign write right after our upload is not adopted as the base")
    func foreignWriteAfterUploadIsNotAdopted() async throws {
        let remote = FakeRemote(etags: ["docs/report.txt": "base"])
        let trip = roundTrip(remote)
        let file = try makeFile("v1")
        try await trip.register(localURL: file, object: object(), etag: "base")

        await remote.writeAfterNextUpload("foreign")
        try Data("v2".utf8).write(to: file)
        #expect(try await trip.syncChanges(at: file) == .uploaded(key: "docs/report.txt"))

        try Data("v3".utf8).write(to: file)
        #expect(try await trip.syncChanges(at: file) == .conflict(copyKey: copyKey))
        #expect(await remote.etags["docs/report.txt"] == "foreign")
    }

    @Test("A server-side change leads to a conflict copy, the original stays")
    func remoteChangeCreatesConflictCopy() async throws {
        let remote = FakeRemote(etags: ["docs/report.txt": "base"])
        let trip = roundTrip(remote)
        let file = try makeFile("v1")
        try await trip.register(localURL: file, object: object(), etag: "base")

        await remote.setETag("someone-else", for: "docs/report.txt")
        try Data("mine".utf8).write(to: file)

        #expect(try await trip.syncChanges(at: file) == .conflict(copyKey: copyKey))
        #expect(await remote.etags["docs/report.txt"] == "someone-else")
        #expect(await remote.uploads.map(\.key) == [copyKey])
        #expect(await remote.uploads.map(\.precondition) == [.ifAbsent])
    }

    @Test("Two conflicts in the same second never replace each other's copy")
    func sameSecondConflictsKeepBothCopies() async throws {
        let remote = FakeRemote(etags: ["docs/report.txt": "base"])
        let tags = TagSequence(["aaaaaa", "aaaaaa", "bbbbbb"])
        let first = roundTrip(remote, tags: tags)
        let second = roundTrip(remote, tags: tags)
        let fileA = try makeFile("a")
        let fileB = try makeFile("b")
        try await first.register(localURL: fileA, object: object(), etag: "base")
        try await second.register(localURL: fileB, object: object(), etag: "base")

        await remote.setETag("someone-else", for: "docs/report.txt")
        try Data("mine A".utf8).write(to: fileA)
        try Data("mine B".utf8).write(to: fileB)

        let copyB = "docs/report (conflict 2026-11-02 12.05.33 bbbbbb).txt"
        #expect(try await first.syncChanges(at: fileA) == .conflict(copyKey: copyKey))
        #expect(try await second.syncChanges(at: fileB) == .conflict(copyKey: copyB))
        #expect(await remote.uploads.map(\.key) == [copyKey, copyB])
    }

    @Test("A 412 on upload is handled like a server-side change")
    func preconditionFailureCreatesConflictCopy() async throws {
        let remote = FakeRemote(etags: ["docs/report.txt": "base"])
        let trip = roundTrip(remote)
        let file = try makeFile("v1")
        try await trip.register(localURL: file, object: object(), etag: "base")

        await remote.failNextConditional()
        try Data("mine".utf8).write(to: file)

        #expect(try await trip.syncChanges(at: file) == .conflict(copyKey: copyKey))
    }

    @Test("A deleted object is not silently recreated")
    func deletedObjectCreatesConflictCopy() async throws {
        let remote = FakeRemote(etags: ["docs/report.txt": "base"])
        let trip = roundTrip(remote)
        let file = try makeFile("v1")
        try await trip.register(localURL: file, object: object(), etag: "base")

        await remote.setETag(nil, for: "docs/report.txt")
        try Data("mine".utf8).write(to: file)

        #expect(try await trip.syncChanges(at: file) == .conflict(copyKey: copyKey))
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
        #expect(try await trip.syncChanges(at: file) == .uploaded(key: copyKey))
        #expect(await remote.uploads.map(\.precondition) == [.ifAbsent, .ifMatch("etag-1")])
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
        #expect(await remote.uploads.map(\.precondition) == [.ifMatch("base")])
    }
}
