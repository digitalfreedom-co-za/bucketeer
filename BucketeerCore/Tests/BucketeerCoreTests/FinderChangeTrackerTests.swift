//
//  FinderChangeTrackerTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

@Suite("FinderChangeTracker")
struct FinderChangeTrackerTests {

    /// A bucket as a flat key → ETag map; lists one folder level the
    /// way the browser does (direct files plus sub-folder entries).
    final class FakeBucket: @unchecked Sendable {
        private let lock = NSLock()
        private var objects: [String: String]

        init(_ objects: [String: String]) { self.objects = objects }

        func delete(_ key: String) { lock.withLock { _ = objects.removeValue(forKey: key) } }

        func list(_ prefix: String) -> [S3Object] {
            lock.withLock {
                var result: [String: S3Object] = [:]
                for (key, etag) in objects where key.hasPrefix(prefix) && key != prefix {
                    let rest = key.dropFirst(prefix.count)
                    if let slash = rest.firstIndex(of: "/") {
                        let folder = prefix + rest[...slash]
                        result[folder] = FinderChangeTrackerTests.object(folder, etag: "", isFolder: true)
                    } else {
                        result[key] = FinderChangeTrackerTests.object(key, etag: etag)
                    }
                }
                return result.values.sorted { $0.key < $1.key }
            }
        }
    }

    /// Holds listers inside their await until opened.
    actor Gate {
        private var armed = true
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private var entered: [CheckedContinuation<Void, Never>] = []
        private var arrivals = 0

        func pass() async {
            guard armed else { return }
            arrivals += 1
            entered.forEach { $0.resume() }
            entered = []
            await withCheckedContinuation { waiting.append($0) }
        }

        /// Returns once at least `count` listers are waiting.
        func untilWaiting(_ count: Int = 1) async {
            while arrivals < count {
                await withCheckedContinuation { entered.append($0) }
            }
        }

        func open() {
            armed = false
            waiting.forEach { $0.resume() }
            waiting = []
        }
    }

    static func object(_ key: String, etag: String, isFolder: Bool = false) -> S3Object {
        S3Object(
            key: key,
            size: 1,
            lastModified: Date(timeIntervalSince1970: 0),
            etag: etag,
            isFolder: isFolder
        )
    }

    private let domain = "domain"

    private func tracker() -> FinderChangeTracker {
        FinderChangeTracker(storageDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("FinderChangeTrackerTests-\(UUID().uuidString)", isDirectory: true))
    }

    private func lister(_ bucket: FakeBucket, gate: Gate? = nil) -> FinderChangeTracker.Lister {
        { prefix in
            await gate?.pass()
            return bucket.list(prefix)
        }
    }

    @Test("A file Finder saw in a folder and that is deleted before the first change request is reported")
    func deletionAfterEnumerationIsReported() async throws {
        let bucket = FakeBucket(["docs/a.txt": "1", "docs/b.txt": "1"])
        let tracker = tracker()
        let anchor = try await tracker.currentAnchor(domain: domain, list: lister(bucket))

        await tracker.record(bucket.list("docs/"), under: "docs/", domain: domain)
        bucket.delete("docs/a.txt")

        let changes = try await tracker.changes(since: anchor, domain: domain, list: lister(bucket))
        #expect(changes.deleted == ["docs/a.txt"])
        #expect(changes.updated.isEmpty)
    }

    @Test("Items from every page of a paginated folder are in the baseline")
    func paginatedEnumerationIsRecorded() async throws {
        let bucket = FakeBucket(["docs/a.txt": "1", "docs/b.txt": "1", "docs/c.txt": "1"])
        let tracker = tracker()
        let anchor = try await tracker.currentAnchor(domain: domain, list: lister(bucket))

        let all = bucket.list("docs/")
        await tracker.record(Array(all.prefix(2)), under: "docs/", domain: domain)
        await tracker.record(Array(all.dropFirst(2)), under: "docs/", domain: domain)
        bucket.delete("docs/a.txt")
        bucket.delete("docs/c.txt")

        let changes = try await tracker.changes(since: anchor, domain: domain, list: lister(bucket))
        #expect(changes.deleted == ["docs/a.txt", "docs/c.txt"])
    }

    @Test("A folder opened while a change request is listing stays tracked")
    func folderTrackedDuringListingSurvives() async throws {
        let bucket = FakeBucket(["docs/a.txt": "1", "docs/b.txt": "1", "top.txt": "1"])
        let tracker = tracker()
        let anchor = try await tracker.currentAnchor(domain: domain, list: lister(bucket))

        let gate = Gate()
        let pending = Task { try await tracker.changes(since: anchor, domain: domain, list: lister(bucket, gate: gate)) }
        await gate.untilWaiting()
        await tracker.record(bucket.list("docs/"), under: "docs/", domain: domain)
        await gate.open()
        let first = try await pending.value

        bucket.delete("docs/a.txt")
        let second = try await tracker.changes(since: first.anchor, domain: domain, list: lister(bucket))
        #expect(second.deleted == ["docs/a.txt"])
    }

    @Test("Of two change requests from the same anchor only one commits")
    func concurrentRequestsDoNotBothCommit() async throws {
        let bucket = FakeBucket(["top.txt": "1"])
        let tracker = tracker()
        let anchor = try await tracker.currentAnchor(domain: domain, list: lister(bucket))

        let gate = Gate()
        let one = Task { try await tracker.changes(since: anchor, domain: domain, list: lister(bucket, gate: gate)) }
        let two = Task { try await tracker.changes(since: anchor, domain: domain, list: lister(bucket, gate: gate)) }
        await gate.untilWaiting(2)
        await gate.open()

        let results = [await one.result, await two.result]
        let committed = results.compactMap { try? $0.get() }
        #expect(committed.count == 1)
        #expect(results.contains { result in
            if case .failure(FinderChangeTracker.TrackerError.anchorExpired) = result { return true }
            return false
        })
    }

    @Test("A cancelled change request does not commit")
    func cancelledRequestDoesNotCommit() async throws {
        let bucket = FakeBucket(["top.txt": "1"])
        let tracker = tracker()
        let anchor = try await tracker.currentAnchor(domain: domain, list: lister(bucket))

        let gate = Gate()
        let pending = Task { try await tracker.changes(since: anchor, domain: domain, list: lister(bucket, gate: gate)) }
        await gate.untilWaiting()
        pending.cancel()
        await gate.open()
        _ = await pending.result

        // The original anchor is still the current one.
        let changes = try await tracker.changes(since: anchor, domain: domain, list: lister(bucket))
        #expect(changes.deleted.isEmpty)
    }

    @Test("An unknown anchor expires")
    func unknownAnchorExpires() async throws {
        let tracker = tracker()
        await #expect(throws: FinderChangeTracker.TrackerError.self) {
            _ = try await tracker.changes(since: "nope", domain: domain, list: lister(FakeBucket([:])))
        }
    }
}
