//
//  MultipartUploadCheckpointTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import Testing
@testable import BucketeerCore

@Suite("MultipartUploadCheckpoint.fingerprint")
struct MultipartUploadCheckpointTests {

    /// Writes one byte to a unique temp URL and returns it.
    /// Caller is responsible for cleanup.
    private static func makeTempFile(contents: Data = Data([0x42])) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bucketeer-test-\(UUID().uuidString).bin")
        try contents.write(to: url)
        return url
    }

    @Test("Fingerprint is stable for the same file across calls")
    func stableAcrossCalls() throws {
        let url = try Self.makeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let first = MultipartUploadCheckpoint.fingerprint(for: url)
        let second = MultipartUploadCheckpoint.fingerprint(for: url)
        #expect(first == second)
        #expect(!first.isEmpty)
    }

    @Test("Fingerprint changes when content is overwritten (different mtime)")
    func changesOnWrite() async throws {
        let url = try Self.makeTempFile(contents: Data([0x01]))
        defer { try? FileManager.default.removeItem(at: url) }
        let initial = MultipartUploadCheckpoint.fingerprint(for: url)
        // Sleep 50ms — well below the previous second-precision
        // bug threshold, but Codex R3's nanosecond fix should
        // still flip the fingerprint.
        try await Task.sleep(nanoseconds: 50_000_000)
        try Data([0x02, 0x03]).write(to: url)
        let after = MultipartUploadCheckpoint.fingerprint(for: url)
        #expect(initial != after)
    }

    @Test("Fingerprint differs for two different files of identical size")
    func differsAcrossFiles() throws {
        let a = try Self.makeTempFile(contents: Data([0xAA]))
        let b = try Self.makeTempFile(contents: Data([0xBB]))
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
        }
        // Same size (1 byte), different paths → different inodes
        // → different fingerprints.
        #expect(MultipartUploadCheckpoint.fingerprint(for: a)
                != MultipartUploadCheckpoint.fingerprint(for: b))
    }

    @Test("Fingerprint for a non-existent URL is the zero-baseline")
    func missingFile() {
        let missing = URL(fileURLWithPath: "/tmp/bucketeer-does-not-exist-\(UUID().uuidString)")
        let fp = MultipartUploadCheckpoint.fingerprint(for: missing)
        // mtime + size + inode all zero → "0|0|0"
        #expect(fp == "0|0|0")
    }
}
