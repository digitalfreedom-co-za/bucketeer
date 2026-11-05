//
//  LocalFolderWriterInstallTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 05.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// The folder enumeration skips hidden files, so a destination folder
/// that holds only hidden files looks empty to the sync planner. A
/// downloaded file of the same name must never replace that folder.
@Suite("LocalFolderWriter.install")
struct LocalFolderWriterInstallTests {

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalFolderWriterInstallTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeStagedFile(_ contents: String) throws -> URL {
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(contents.utf8).write(to: staged)
        return staged
    }

    @Test("A folder at the destination is never replaced by a file")
    func folderIsNotReplaced() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let hidden = root.appendingPathComponent("config/.env")
        try FileManager.default.createDirectory(at: hidden.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("SECRET=1".utf8).write(to: hidden)
        let staged = try makeStagedFile("remote")
        defer { try? FileManager.default.removeItem(at: staged) }

        #expect(throws: BucketeerError.self) {
            try LocalFolderWriter.install(from: staged, relativeKey: "config", under: root)
        }
        #expect(try String(contentsOf: hidden, encoding: .utf8) == "SECRET=1")
    }

    @Test("An existing file at the destination is replaced")
    func fileIsReplaced() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("notes.txt")
        try Data("old".utf8).write(to: destination)
        let staged = try makeStagedFile("new")

        try LocalFolderWriter.install(from: staged, relativeKey: "notes.txt", under: root)

        #expect(try String(contentsOf: destination, encoding: .utf8) == "new")
    }
}
