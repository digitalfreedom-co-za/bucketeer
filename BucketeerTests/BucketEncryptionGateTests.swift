//
//  BucketEncryptionGateTests.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import XCTest
import BucketeerCore

/// Rule: once encryption is turned on for a bucket, no transfer may
/// still see the bucket as unencrypted — not even one whose lookup was
/// already running. In-memory key store only.
final class BucketEncryptionGateTests: XCTestCase {
    private let accountID = UUID()

    func testKeyAddedDuringALookupIsNotHiddenByTheStaleAnswer() async throws {
        let store = GatedKeyStore()
        let gate = BucketEncryptionGate(keyStore: store)
        let lookup = Task { [accountID] in try await gate.key(accountID: accountID, bucket: "photos") }
        await store.waitUntilHolding()

        await store.addKey(accountID: accountID, bucket: "photos")
        await gate.invalidate(accountID: accountID, bucket: "photos")
        await store.release()

        let pendingAnswer = try await lookup.value
        let laterAnswer = try await gate.key(accountID: accountID, bucket: "photos")
        XCTAssertNotNil(pendingAnswer)
        XCTAssertNotNil(laterAnswer)
    }
}

/// Key store whose first lookup parks until `release()` and answers with
/// the keys it had when the lookup started.
private actor GatedKeyStore: EncryptionKeyStoring {
    private var keys: [BucketEncryptionKey] = []
    private var holdsNext = true
    private var gate: CheckedContinuation<Void, Never>?

    func waitUntilHolding() async {
        while gate == nil { await Task.yield() }
    }

    func release() {
        gate?.resume()
        gate = nil
    }

    func addKey(accountID: UUID, bucket: String) {
        keys.append(BucketEncryptionKey(label: "Key", accountID: accountID, bucket: bucket))
    }

    func all() -> [BucketEncryptionKey] { keys }

    func key(accountID: UUID, bucket: String) async -> BucketEncryptionKey? {
        let answer = keys.first { $0.accountID == accountID && $0.bucket == bucket }
        if holdsNext {
            holdsNext = false
            await withCheckedContinuation { gate = $0 }
        }
        return answer
    }

    func create(label: String, accountID: UUID, bucket: String) -> BucketEncryptionKey {
        let key = BucketEncryptionKey(label: label, accountID: accountID, bucket: bucket)
        keys.append(key)
        return key
    }

    func keyMaterial(id: UUID) -> Data { Data(count: 32) }

    func delete(id: UUID) {
        keys.removeAll { $0.id == id }
    }
}
