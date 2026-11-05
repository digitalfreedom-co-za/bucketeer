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

    // MARK: - Local files (a temp folder; a "trash" folder inside it stands in for the Trash)

    private func makeRoot() throws -> (root: URL, trash: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VersionedDeleteTests-\(UUID().uuidString)", isDirectory: true)
        let trash = root.appendingPathComponent("trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        return (root, trash)
    }

    private func setAside(into trash: URL) -> (URL) throws -> URL? {
        { url in
            let kept = trash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: kept)
            return kept
        }
    }

    private func fingerprint(of key: String, under root: URL) throws -> LocalFileFingerprint {
        LocalFileFingerprint(try LocalFolderEnumerator.enumerate(at: root).first { $0.key == key }!)
    }

    @Test("A local file edited after it was listed is kept")
    func editedLocalFileIsKept() throws {
        let (root, trash) = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let edited = root.appendingPathComponent("edited.txt")
        let untouched = root.appendingPathComponent("untouched.txt")
        try Data("AAAA".utf8).write(to: edited)
        try Data("AAAA".utf8).write(to: untouched)
        let editedPrint = try fingerprint(of: "edited.txt", under: root)
        let untouchedPrint = try fingerprint(of: "untouched.txt", under: root)
        try Data("BBBB".utf8).write(to: edited)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: edited.path)

        #expect(try !LocalFolderWriter.deleteIfUnchanged(relativeKey: "edited.txt", under: root,
                                                         fingerprint: editedPrint, discard: setAside(into: trash)))
        #expect(try LocalFolderWriter.deleteIfUnchanged(relativeKey: "untouched.txt", under: root,
                                                        fingerprint: untouchedPrint, discard: setAside(into: trash)))
        #expect(FileManager.default.fileExists(atPath: edited.path))
        #expect(!FileManager.default.fileExists(atPath: untouched.path))
    }

    @Test("A folder that took the listed file's place is kept with its contents")
    func folderInPlaceOfListedFileIsKept() throws {
        let (root, trash) = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("notes.txt")
        // A whole second, so the folder below can carry exactly this date.
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try Data().write(to: path)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path.path)
        let listed = try fingerprint(of: "notes.txt", under: root)
        // Between planning and deleting, the file becomes a folder with
        // the listed date: a folder has no size, so only its type tells
        // it apart.
        try FileManager.default.removeItem(at: path)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        try Data("keep".utf8).write(to: path.appendingPathComponent("keep.txt"))
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path.path)

        #expect(try !LocalFolderWriter.deleteIfUnchanged(relativeKey: "notes.txt", under: root,
                                                         fingerprint: listed, discard: setAside(into: trash)))
        #expect(try Data(contentsOf: path.appendingPathComponent("keep.txt")) == Data("keep".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["notes.txt", "trash"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
    }

    @Test("A write through a handle opened before the move survives the source removal")
    func lateWriteThroughOpenHandleSurvives() throws {
        let (root, trash) = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("notes.txt")
        try Data("AAAA".utf8).write(to: source)
        let listed = try fingerprint(of: "notes.txt", under: root)
        // An editor that already has the file open.
        let editor = try FileHandle(forWritingTo: source)

        let removed = try LocalFolderWriter.deleteIfUnchanged(
            relativeKey: "notes.txt", under: root, fingerprint: listed, discard: setAside(into: trash)
        )
        try editor.seekToEnd()
        try editor.write(contentsOf: Data("BB".utf8))
        try editor.close()

        #expect(removed)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: trash.appendingPathComponent("notes.txt")) == Data("AAAABB".utf8))
    }

    @Test("A source that cannot be set aside stays under its name")
    func sourceStaysWhenItCannotBeSetAside() throws {
        let (root, _) = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("notes.txt")
        try Data("AAAA".utf8).write(to: source)
        let listed = try fingerprint(of: "notes.txt", under: root)
        struct NoTrash: Error {}

        #expect(throws: NoTrash.self) {
            try LocalFolderWriter.deleteIfUnchanged(relativeKey: "notes.txt", under: root, fingerprint: listed,
                                                    discard: { _ in throw NoTrash() })
        }

        #expect(try Data(contentsOf: source) == Data("AAAA".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["notes.txt", "trash"])
    }
}
