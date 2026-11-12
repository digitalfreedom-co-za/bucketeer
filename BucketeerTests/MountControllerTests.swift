//
//  MountControllerTests.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import XCTest
import FileProvider
import BucketeerCore

/// Rule: a bucket is never both mounted in Finder and encrypted, because
/// the File Provider extension moves raw bytes. Runs against a fake
/// domain registry and an in-memory key store; no real Finder domain.
@MainActor
final class MountControllerTests: XCTestCase {
    private let account = S3Account(name: "Demo", provider: .awsS3)

    func testEncryptedBucketIsNotMounted() async {
        let keyStore = FakeKeyStore(keys: [BucketEncryptionKey(label: "Key", accountID: account.id, bucket: "photos")])
        let registry = FakeDomainRegistry()
        let controller = MountController(encryptionKeyStore: keyStore, registry: registry)

        await controller.mount(account: account, bucket: "photos")

        XCTAssertTrue(registry.registered.isEmpty)
        XCTAssertNotNil(controller.lastError)
    }

    func testEncryptionStaysOffWhenTheMountStateIsUnknown() async {
        let registry = FakeDomainRegistry()
        registry.lookupFails = true
        let controller = MountController(encryptionKeyStore: FakeKeyStore(), registry: registry)
        var ranOperation = false

        do {
            try await controller.whileUnmounted(account: account, bucket: "photos") { ranOperation = true }
            XCTFail("a failed domain lookup must refuse")
        } catch {}

        XCTAssertFalse(ranOperation)
    }

    func testEncryptionIsRefusedForAMountedBucket() async {
        let registry = FakeDomainRegistry()
        registry.registered = [MountController.domainIdentifier(accountID: account.id, bucket: "photos")]
        let controller = MountController(encryptionKeyStore: FakeKeyStore(), registry: registry)
        var ranOperation = false

        do {
            try await controller.whileUnmounted(account: account, bucket: "photos") { ranOperation = true }
            XCTFail("a mounted bucket must refuse")
        } catch {}

        XCTAssertFalse(ranOperation)
    }

    func testEncryptionIsRefusedWhileAMountIsInFlight() async throws {
        let registry = FakeDomainRegistry()
        registry.holdsAdd = true
        let controller = MountController(encryptionKeyStore: FakeKeyStore(), registry: registry)
        let mount = Task { await controller.mount(account: account, bucket: "photos") }
        try await waitUntil { registry.addStarted }
        var ranOperation = false

        do {
            try await controller.whileUnmounted(account: account, bucket: "photos") { ranOperation = true }
            XCTFail("encryption must wait for the mount to finish")
        } catch {}
        registry.releaseAdd()
        await mount.value

        XCTAssertFalse(ranOperation)
        XCTAssertEqual(registry.registered.count, 1)
    }

    func testMountIsRefusedWhileEncryptionIsBeingTurnedOn() async throws {
        let registry = FakeDomainRegistry()
        let controller = MountController(encryptionKeyStore: FakeKeyStore(), registry: registry)
        let gate = OperationGate()
        let enable = Task {
            try await controller.whileUnmounted(account: account, bucket: "photos") { await gate.hold() }
        }
        try await waitUntil { gate.isHolding }

        await controller.mount(account: account, bucket: "photos")
        gate.release()
        try await enable.value

        XCTAssertTrue(registry.registered.isEmpty)
        XCTAssertNotNil(controller.lastError)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        var attempts = 0
        while !condition() && attempts < 1_000 {
            await Task.yield()
            attempts += 1
        }
        XCTAssertTrue(condition(), "the operation never reached its suspension point")
    }
}

@MainActor
private final class FakeDomainRegistry: FileProviderDomainRegistry {
    var registered: [NSFileProviderDomainIdentifier] = []
    var lookupFails = false
    var holdsAdd = false
    private(set) var addStarted = false
    private let addGate = OperationGate()

    func identifiers() async throws -> [NSFileProviderDomainIdentifier] {
        if lookupFails { throw CocoaError(.fileReadUnknown) }
        return registered
    }

    func add(identifier: NSFileProviderDomainIdentifier, displayName: String) async throws {
        addStarted = true
        if holdsAdd { await addGate.hold() }
        registered.append(identifier)
    }

    func remove(identifier: NSFileProviderDomainIdentifier) async throws {
        registered.removeAll { $0 == identifier }
    }

    func signalWorkingSet(identifier: NSFileProviderDomainIdentifier) async throws {}

    func releaseAdd() {
        addGate.release()
    }
}

/// Suspends a caller until the test releases it.
@MainActor
private final class OperationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var isHolding: Bool { continuation != nil }

    func hold() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor FakeKeyStore: EncryptionKeyStoring {
    private var keys: [BucketEncryptionKey]

    init(keys: [BucketEncryptionKey] = []) {
        self.keys = keys
    }

    func all() -> [BucketEncryptionKey] { keys }

    func key(accountID: UUID, bucket: String) -> BucketEncryptionKey? {
        keys.first { $0.accountID == accountID && $0.bucket == bucket }
    }

    func create(label: String, accountID: UUID, bucket: String) -> BucketEncryptionKey {
        let key = BucketEncryptionKey(label: label, accountID: accountID, bucket: bucket)
        keys.append(key)
        return key
    }

    func copyForReassignment(_ key: BucketEncryptionKey, to accountID: UUID) throws -> BucketEncryptionKey {
        throw CocoaError(.featureUnsupported)
    }

    func importKey(_ entry: KeyBackupEntry, replacing expectedID: UUID?) throws {
        throw CocoaError(.featureUnsupported)
    }

    func markBackupReady(id: UUID) throws {
        throw CocoaError(.featureUnsupported)
    }

    func keyMaterial(id: UUID) -> Data { Data(count: 32) }

    func delete(id: UUID) {
        keys.removeAll { $0.id == id }
    }
}
