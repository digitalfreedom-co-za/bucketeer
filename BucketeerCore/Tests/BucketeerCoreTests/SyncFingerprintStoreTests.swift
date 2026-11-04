//
//  SyncFingerprintStoreTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// The acknowledged state of a job's local files must outlive the app,
/// or every launch would forget which same-size edits were synced.
@Suite("SyncFingerprintStore")
struct SyncFingerprintStoreTests {

    @Test("Fingerprints survive reopening the store, per job, and vanish with their job")
    func persistsPerJob() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncFingerprintStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Fingerprints.store")
        let job = UUID()
        let removedJob = UUID()
        let fingerprint = LocalFileFingerprint(size: 4, modified: Date(timeIntervalSince1970: 1_800_000_000))

        let store = SyncFingerprintStore(modelContainer: try SyncFingerprintStore.makeContainer(url: url))
        try await store.replace(jobID: job, with: ["a.txt": fingerprint])
        try await store.replace(jobID: removedJob, with: ["b.txt": fingerprint])

        let reopened = SyncFingerprintStore(modelContainer: try SyncFingerprintStore.makeContainer(url: url))
        #expect(try await reopened.fingerprints(jobID: job) == ["a.txt": fingerprint])
        try await reopened.removeAll(except: [job])
        #expect(try await reopened.fingerprints(jobID: removedJob).isEmpty)
        #expect(try await reopened.fingerprints(jobID: job) == ["a.txt": fingerprint])
    }
}
