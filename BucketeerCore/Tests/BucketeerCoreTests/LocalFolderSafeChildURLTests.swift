//
//  LocalFolderSafeChildURLTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// Locks down the path-traversal guard introduced in the Codex Phase
/// 9.8 review (blocker #1). A failure here means an attacker-controlled
/// S3 key could escape the chosen sync root and write to (or delete
/// from) arbitrary paths the app sandbox can reach.
@Suite("LocalFolderWriter.safeChildURL")
struct LocalFolderSafeChildURLTests {

    private let root = URL(fileURLWithPath: "/tmp/bucketeer-sync-root", isDirectory: true)

    @Test("Empty relative key is rejected")
    func emptyKeyRejected() {
        #expect(throws: BucketeerError.self) {
            _ = try LocalFolderWriter.safeChildURL(root: root, relativeKey: "")
        }
        #expect(throws: BucketeerError.self) {
            _ = try LocalFolderWriter.safeChildURL(root: root, relativeKey: "   ")
        }
    }

    @Test("Absolute paths are rejected")
    func absolutePathsRejected() {
        for badKey in ["/etc/passwd", "/Users/marcel/Documents/secret.txt", "\\Windows\\System32"] {
            #expect(throws: BucketeerError.self) {
                _ = try LocalFolderWriter.safeChildURL(root: root, relativeKey: badKey)
            }
        }
    }

    @Test("Single .. component is rejected")
    func singleDotDotRejected() {
        #expect(throws: BucketeerError.self) {
            _ = try LocalFolderWriter.safeChildURL(root: root, relativeKey: "..")
        }
    }

    @Test("Embedded .. components are rejected")
    func embeddedDotDotRejected() {
        for badKey in [
            "../etc/passwd",
            "subdir/../../etc/passwd",
            "a/b/../../../outside.txt",
            "./relative.txt",
            "subdir/./inner.txt"
        ] {
            #expect(throws: BucketeerError.self) {
                _ = try LocalFolderWriter.safeChildURL(root: root, relativeKey: badKey)
            }
        }
    }

    @Test("Legitimate relative keys resolve under the root")
    func legitimateKeysAccepted() throws {
        let cases: [(input: String, expectedSuffix: String)] = [
            ("a.txt",                  "/bucketeer-sync-root/a.txt"),
            ("photos/2026/05/img.jpg", "/bucketeer-sync-root/photos/2026/05/img.jpg"),
            ("with space.bin",         "/bucketeer-sync-root/with space.bin"),
            ("nested/deep/path.dat",   "/bucketeer-sync-root/nested/deep/path.dat")
        ]
        for entry in cases {
            let resolved = try LocalFolderWriter.safeChildURL(root: root, relativeKey: entry.input)
            #expect(resolved.path.hasSuffix(entry.expectedSuffix))
            // Also: the resolved path is strictly inside the root.
            #expect(resolved.path.hasPrefix(root.standardizedFileURL.path + "/"))
        }
    }

    @Test("Symlink-style relative keys are still anchored to root via standardization")
    func resolvedPathStaysUnderRoot() throws {
        // A key with multiple internal slashes still resolves under root.
        let resolved = try LocalFolderWriter.safeChildURL(
            root: root,
            relativeKey: "subdir//file.txt"
        )
        #expect(resolved.path.hasPrefix(root.standardizedFileURL.path + "/"))
    }
}
