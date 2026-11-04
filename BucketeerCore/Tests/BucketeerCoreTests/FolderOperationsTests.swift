//
//  FolderOperationsTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// A folder in a bucket is only a key prefix: deleting or renaming it
/// has to reach every object below it, not just the `folder/` marker.
@Suite("FolderOperations")
struct FolderOperationsTests {

    private let account = S3Account(name: "Test", provider: .awsS3)

    private func bucket() async -> InMemoryS3Browser {
        let browser = InMemoryS3Browser(pageSize: 2)
        for key in ["docs/", "docs/a.txt", "docs/sub/b.txt", "docs/sub/c.txt", "docs-old.txt", "other/d.txt"] {
            await browser.put(bucket: "b", key: key)
        }
        return browser
    }

    private func keys(in browser: InMemoryS3Browser) async throws -> Set<String> {
        await browser.storedKeys(in: "b")
    }

    @Test("Deleting a folder removes every descendant and leaves its neighbours")
    func deleteReachesDescendants() async throws {
        let browser = await bucket()
        let contents = try await FolderOperations.contents(of: "docs/", browser: browser, account: account, bucket: "b")

        try await FolderOperations.delete(contents, browser: browser, account: account, bucket: "b")

        #expect(try await keys(in: browser) == ["docs-old.txt", "other/d.txt"])
    }

    @Test("Renaming a folder moves every descendant to the new prefix")
    func renameMovesDescendants() async throws {
        let browser = await bucket()
        let contents = try await FolderOperations.contents(of: "docs/", browser: browser, account: account, bucket: "b")

        let kept = try await FolderOperations.move(contents, to: "papers/", browser: browser, account: account, bucket: "b")

        #expect(kept.isEmpty)
        #expect(try await keys(in: browser) == [
            "papers/", "papers/a.txt", "papers/sub/b.txt", "papers/sub/c.txt", "docs-old.txt", "other/d.txt"
        ])
    }

    @Test("A rename onto an existing folder changes nothing")
    func renameRefusesExistingDestination() async throws {
        let browser = await bucket()
        let before = try await keys(in: browser)
        let contents = try await FolderOperations.contents(of: "docs/", browser: browser, account: account, bucket: "b")

        await #expect(throws: BucketeerError.self) {
            _ = try await FolderOperations.move(contents, to: "other/", browser: browser, account: account, bucket: "b")
        }

        #expect(try await keys(in: browser) == before)
    }

    @Test("A file changed during the rename stays at its old key and is reported")
    func renameKeepsChangedSource() async throws {
        let browser = await bucket()
        let contents = try await FolderOperations.contents(of: "docs/", browser: browser, account: account, bucket: "b")
        await browser.rewrite(bucket: "b", key: "docs/sub/b.txt")

        let kept = try await FolderOperations.move(contents, to: "papers/", browser: browser, account: account, bucket: "b")

        #expect(kept == ["docs/sub/b.txt"])
        #expect(try await keys(in: browser).contains("docs/sub/b.txt"))
        #expect(try await keys(in: browser).contains("papers/sub/b.txt"))
    }
}
