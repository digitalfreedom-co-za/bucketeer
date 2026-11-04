//
//  OpenWithRecoveryTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

@Suite("Open With recovery")
struct OpenWithRecoveryTests {

    /// Server double that can be taken offline and can simulate the
    /// editor writing again while an upload is in flight.
    actor Remote: OpenWithRemote {
        private(set) var etags: [String: String]
        private(set) var uploads: [WritePrecondition] = []
        private var offline = false
        private var writeDuringUpload: (url: URL, contents: String)?
        private var counter = 0

        init(etags: [String: String]) { self.etags = etags }

        func setOffline(_ value: Bool) { offline = value }
        func editDuringNextUpload(_ url: URL, _ contents: String) { writeDuringUpload = (url, contents) }

        func currentETag(of object: RemoteObjectRef) async throws -> String? {
            if offline { throw BucketeerError.networkUnavailable }
            return etags[object.key]
        }

        func upload(
            _ localURL: URL,
            to object: RemoteObjectRef,
            precondition: WritePrecondition
        ) async throws -> ConditionalUploadResult {
            if offline { throw BucketeerError.networkUnavailable }
            if case .ifMatch(let base) = precondition, etags[object.key] != base { return .preconditionFailed }
            uploads.append(precondition)
            counter += 1
            etags[object.key] = "etag-\(counter)"
            if let edit = writeDuringUpload {
                writeDuringUpload = nil
                try Data(edit.contents.utf8).write(to: edit.url)
            }
            return .uploaded(etag: "etag-\(counter)")
        }
    }

    private let accountID = UUID()
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("OpenWithRecoveryTests-\(UUID().uuidString)", isDirectory: true)

    private var object: RemoteObjectRef {
        RemoteObjectRef(accountID: accountID, bucket: "bucket", key: "docs/report.txt")
    }

    private func workspace(session: String = UUID().uuidString) -> OpenWithWorkspace {
        OpenWithWorkspace(
            workRoot: root.appendingPathComponent("work", isDirectory: true),
            recoveryRoot: root.appendingPathComponent("recovery", isDirectory: true),
            sessionID: session
        )
    }

    /// Downloads "v1" into a fresh folder of `workspace` and registers it.
    private func openFile(_ trip: OpenWithRoundTrip, in workspace: OpenWithWorkspace) async throws -> URL {
        let url = try workspace.makeFileFolder().appendingPathComponent("report.txt")
        try Data("v1".utf8).write(to: url)
        try await trip.register(localURL: url, object: object, etag: "base")
        return url
    }

    private func contents(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    @Test("A clean close removes the temp copy")
    func cleanCloseRemoves() async throws {
        let remote = Remote(etags: ["docs/report.txt": "base"])
        let space = workspace()
        let trip = OpenWithRoundTrip(remote: remote, workspace: space)
        let file = try await openFile(trip, in: space)
        try Data("v2".utf8).write(to: file)

        let result = await trip.close(file)

        #expect(result.retained == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(space.recoveries().isEmpty)
        #expect(await remote.uploads == [.ifMatch("base")])
    }

    @Test("A save that cannot be uploaded is kept with its remote identity")
    func failedSyncIsRetained() async throws {
        let remote = Remote(etags: ["docs/report.txt": "base"])
        let space = workspace()
        let trip = OpenWithRoundTrip(remote: remote, workspace: space)
        let file = try await openFile(trip, in: space)
        try Data("my edit".utf8).write(to: file)
        await remote.setOffline(true)

        let result = await trip.close(file)

        let kept = try #require(result.retained)
        #expect(try contents(kept.fileURL) == "my edit")
        #expect(kept.manifest.object == object)
        #expect(kept.manifest.etag == "base")
        #expect(space.recoveries() == [kept])
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("An edit written after the final upload is kept, not deleted")
    func editDuringFinalSyncIsRetained() async throws {
        let remote = Remote(etags: ["docs/report.txt": "base"])
        let space = workspace()
        let trip = OpenWithRoundTrip(remote: remote, workspace: space)
        let file = try await openFile(trip, in: space)
        try Data("v2".utf8).write(to: file)
        await remote.editDuringNextUpload(file, "v3")

        let result = await trip.close(file)

        let kept = try #require(result.retained)
        #expect(try contents(kept.fileURL) == "v3")
        #expect(kept.manifest.etag == "etag-1")
    }

    @Test("Launch cleanup keeps unsynced crash survivors and removes clean ones")
    func scavengeKeepsDirtySurvivors() async throws {
        let remote = Remote(etags: ["docs/report.txt": "base"])
        let crashed = workspace(session: "crashed")
        let trip = OpenWithRoundTrip(remote: remote, workspace: crashed)
        let dirty = try await openFile(trip, in: crashed)
        let clean = try await openFile(trip, in: crashed)
        try Data("unsaved work".utf8).write(to: dirty)
        // The app dies here: no close, no upload.

        let next = workspace(session: "next")
        next.scavengeLeftovers()

        let recovered = next.recoveries()
        #expect(recovered.count == 1)
        #expect(try contents(try #require(recovered.first).fileURL) == "unsaved work")
        #expect(!FileManager.default.fileExists(atPath: clean.path))
        #expect(!FileManager.default.fileExists(atPath: crashed.sessionFolder.path))
    }

    @Test("Launch cleanup never deletes a survivor it could not move to recovery")
    func unmovableSurvivorIsKept() async throws {
        let remote = Remote(etags: ["docs/report.txt": "base"])
        let crashed = workspace(session: "crashed")
        let trip = OpenWithRoundTrip(remote: remote, workspace: crashed)
        let dirty = try await openFile(trip, in: crashed)
        try Data("unsaved work".utf8).write(to: dirty)
        // A file where the recovery folder belongs makes every move fail.
        try Data().write(to: root.appendingPathComponent("recovery"))

        workspace(session: "next").scavengeLeftovers()

        #expect(try contents(dirty) == "unsaved work")
    }

    @Test("Launch cleanup never deletes a survivor it could not read")
    func unreadableSurvivorIsKept() async throws {
        let remote = Remote(etags: ["docs/report.txt": "base"])
        let crashed = workspace(session: "crashed")
        let trip = OpenWithRoundTrip(remote: remote, workspace: crashed)
        let dirty = try await openFile(trip, in: crashed)
        try Data("unsaved work".utf8).write(to: dirty)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: dirty.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dirty.path) }

        workspace(session: "next").scavengeLeftovers()

        #expect(FileManager.default.fileExists(atPath: dirty.path))
    }

    @Test("Launch cleanup never deletes a survivor whose manifest it could not read")
    func unreadableManifestIsKept() async throws {
        let remote = Remote(etags: ["docs/report.txt": "base"])
        let crashed = workspace(session: "crashed")
        let trip = OpenWithRoundTrip(remote: remote, workspace: crashed)
        let dirty = try await openFile(trip, in: crashed)
        try Data("unsaved work".utf8).write(to: dirty)
        let manifest = dirty.deletingLastPathComponent().appendingPathComponent(OpenWithWorkspace.manifestName)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: manifest.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: manifest.path) }

        workspace(session: "next").scavengeLeftovers()

        #expect(try contents(dirty) == "unsaved work")
    }

    @Test("A synced file is not mistaken for a crash survivor")
    func syncedSurvivorIsRemoved() async throws {
        let remote = Remote(etags: ["docs/report.txt": "base"])
        let crashed = workspace(session: "crashed")
        let trip = OpenWithRoundTrip(remote: remote, workspace: crashed)
        let file = try await openFile(trip, in: crashed)
        try Data("v2".utf8).write(to: file)
        _ = try await trip.syncChanges(at: file)

        let next = workspace(session: "next")
        next.scavengeLeftovers()

        #expect(next.recoveries().isEmpty)
    }

    @Test("Retrying a kept save uploads it against the original base and clears it")
    func retryUploadsAndClears() async throws {
        let remote = Remote(etags: ["docs/report.txt": "base"])
        let space = workspace()
        let trip = OpenWithRoundTrip(remote: remote, workspace: space)
        let file = try await openFile(trip, in: space)
        try Data("my edit".utf8).write(to: file)
        await remote.setOffline(true)
        let kept = try #require(await trip.close(file).retained)

        await remote.setOffline(false)
        let retry = await trip.retry(kept)

        #expect(retry.retained == nil)
        #expect(space.recoveries().isEmpty)
        #expect(await remote.uploads == [.ifMatch("base")])
    }

    @Test("A retry that fails again stays in recovery")
    func failedRetryStays() async throws {
        let remote = Remote(etags: ["docs/report.txt": "base"])
        let space = workspace()
        let trip = OpenWithRoundTrip(remote: remote, workspace: space)
        let file = try await openFile(trip, in: space)
        try Data("my edit".utf8).write(to: file)
        await remote.setOffline(true)
        let kept = try #require(await trip.close(file).retained)

        let retry = await trip.retry(kept)

        #expect(retry.retained == kept)
        #expect(space.recoveries() == [kept])
    }

    @Test("Discarding removes a kept save")
    func discardRemoves() async throws {
        let remote = Remote(etags: ["docs/report.txt": "base"])
        let space = workspace()
        let trip = OpenWithRoundTrip(remote: remote, workspace: space)
        let file = try await openFile(trip, in: space)
        try Data("my edit".utf8).write(to: file)
        await remote.setOffline(true)
        let kept = try #require(await trip.close(file).retained)

        space.discard(kept)

        #expect(space.recoveries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: kept.fileURL.path))
    }
}
