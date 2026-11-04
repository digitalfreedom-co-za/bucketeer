//
//  ObjectMoveTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// Renaming one object is a copy plus a delete. Neither may cost data:
/// an object at the new name is never replaced, and a source that
/// changed is never deleted. In-memory browser; no network.
@Suite("ObjectMove")
struct ObjectMoveTests {

    private let account = S3Account(name: "Test", provider: .civo)

    private func browser() async -> InMemoryS3Browser {
        let browser = InMemoryS3Browser()
        await browser.put(bucket: "b", key: "a.txt", size: 3)
        return browser
    }

    @Test("An unchanged object moves to the free name")
    func movesUnchangedObject() async throws {
        let browser = await browser()

        let removed = try await ObjectMove.move("a.txt", etag: "etag-a.txt", to: "b.txt",
                                                browser: browser, account: account, bucket: "b")

        #expect(removed)
        #expect(await browser.storedKeys(in: "b") == ["b.txt"])
    }

    @Test("A taken name is refused and both objects stay")
    func takenNameIsRefused() async throws {
        let browser = await browser()
        await browser.put(bucket: "b", key: "b.txt", size: 9)

        await #expect(throws: BucketeerError.preconditionFailed(key: "b.txt")) {
            _ = try await ObjectMove.move("a.txt", etag: "etag-a.txt", to: "b.txt",
                                          browser: browser, account: account, bucket: "b")
        }

        #expect(await browser.storedKeys(in: "b") == ["a.txt", "b.txt"])
        #expect(try await browser.head(account: account, bucket: "b", key: "b.txt").size == 9)
    }

    @Test("A source changed since it was read is neither copied nor deleted")
    func changedSourceStays() async throws {
        let browser = await browser()
        await browser.rewrite(bucket: "b", key: "a.txt")

        await #expect(throws: BucketeerError.preconditionFailed(key: "b.txt")) {
            _ = try await ObjectMove.move("a.txt", etag: "etag-a.txt", to: "b.txt",
                                          browser: browser, account: account, bucket: "b")
        }

        #expect(await browser.storedKeys(in: "b") == ["a.txt"])
    }
}
