//
//  TransferManagerLifecycleTests.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import XCTest
import BucketeerCore

/// Rules: every observer of the queue sees every terminal state, a
/// cancelled transfer reports completion only once its worker stopped
/// using the file, and an upload that needs a key never goes out
/// without one. Azure requests go to a stub that refuses them; the
/// Keychain and key store are in memory.
final class TransferManagerLifecycleTests: XCTestCase {
    private let account = S3Account(name: "Test", provider: .azureBlob, accountID: "teststorage")
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TransferManagerLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testEverySubscriberSeesTheTerminalState() async throws {
        let manager = try await makeManager()
        let queueView = manager.taskUpdates()
        let autoTagging = manager.taskUpdates()
        let completions = manager.completions()

        let id = await manager.enqueueDownload(account: account, bucket: "c", key: "a.txt",
                                               localURL: folder.appendingPathComponent("a.txt"))

        let first = await firstTerminal(of: id, in: queueView)
        let second = await firstTerminal(of: id, in: autoTagging)
        var completed: TransferTask?
        for await task in completions where task.id == id {
            completed = task
            break
        }
        XCTAssertTrue(first?.isTerminal == true)
        XCTAssertTrue(second?.isTerminal == true)
        XCTAssertEqual(completed?.state, first)
    }

    func testCancelReportsCompletionOnlyAfterTheWorkerStopped() async throws {
        let keyStore = BlockingKeyStore()
        let manager = try await makeManager(encryptionGate: BucketEncryptionGate(keyStore: keyStore))
        let file = folder.appendingPathComponent("upload.txt")
        try Data("payload".utf8).write(to: file)
        let id = await manager.enqueueUpload(account: account, bucket: "c", key: "upload.txt",
                                             localURL: file, contentType: nil)
        await keyStore.waitUntilHolding()

        await manager.cancel(id: id)
        let reported = Flag()
        let waiter = Task {
            let state = await manager.awaitCompletion(id: id)
            await reported.set()
            return state
        }
        try await Task.sleep(for: .milliseconds(200))
        let reportedWhileWorking = await reported.isSet
        await keyStore.release()
        let state = await waiter.value

        XCTAssertFalse(reportedWhileWorking, "completion must wait until the worker no longer uses the file")
        XCTAssertEqual(state, .cancelled)
    }

    func testUploadIntoABucketWhoseKeyWasRemovedAfterThePreflightSendsNothing() async throws {
        let keyStore = InMemoryEncryptionKeyStore(encryptedBuckets: [(account.id, "vault"), (account.id, "keyed")])
        let gate = BucketEncryptionGate(keyStore: keyStore)
        let manager = try await makeManager(encryptionGate: gate)
        let file = folder.appendingPathComponent("plain.txt")
        try Data("plaintext".utf8).write(to: file)
        let destination = await gate.keyState(accountID: account.id, bucket: "keyed")
        XCTAssertEqual(destination, .encrypted)
        for key in await keyStore.all() where key.bucket == "keyed" {
            try await keyStore.delete(id: key.id)
        }
        await gate.invalidate(accountID: account.id, bucket: "keyed")

        for name in ["refused-first.txt", "refused-second.txt"] {
            let refused = await manager.enqueueUpload(
                account: account, bucket: "keyed", key: name,
                localURL: file, contentType: nil, bypassEncryption: false,
                requiresEncryption: destination.requiresEncryption,
                destinationHadKey: destination == .encrypted
            )
            let refusedState = await manager.awaitCompletion(id: refused)
            XCTAssertEqual(refusedState, .failed(message: String(localized: "error.encryptionKeyRemoved")))
            XCTAssertFalse(RefusingAzureStub.requested(blob: name), "no byte may reach the bucket")
        }
        let unrequired = await manager.enqueueUpload(account: account, bucket: "keyed", key: "unrequired.txt",
                                                     localURL: file, contentType: nil)
        _ = await manager.awaitCompletion(id: unrequired)

        XCTAssertTrue(RefusingAzureStub.requested(blob: "unrequired.txt"), "uploads without the requirement still go out")

        let staleKey = await keyStore.create(label: "Stale", accountID: account.id, bucket: "stale")
        await keyStore.failNextDeletes(1)
        do {
            try await keyStore.delete(id: staleKey.id)
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {}
        let missingMaterial = await manager.enqueueUpload(
            account: account, bucket: "stale", key: "missing-material.txt",
            localURL: file, contentType: nil, bypassEncryption: false, destinationHadKey: false
        )
        let missingMaterialState = await manager.awaitCompletion(id: missingMaterial)
        XCTAssertEqual(missingMaterialState, TransferState.failed(message: EncryptionError.keyRemoved.localizedDescription))
    }

    func testUploadDistinguishesLookupFailureFromUnknownPreflightWithoutAKey() async throws {
        let keyStore = InMemoryEncryptionKeyStore(encryptedBuckets: [(account.id, "vault")])
        let gate = BucketEncryptionGate(keyStore: keyStore)
        let manager = try await makeManager(encryptionGate: gate)
        let file = folder.appendingPathComponent("confirmed-copy.txt")
        try Data("plaintext".utf8).write(to: file)
        let destination = await gate.keyState(accountID: account.id, bucket: "public")
        let asksForConsent = await gate.isEncryptedToPlain(
            sourceAccountID: account.id, sourceBucket: "vault",
            destinationAccountID: account.id, destinationBucket: "public",
            destination: destination
        )
        XCTAssertEqual(destination, .plain)
        XCTAssertTrue(asksForConsent)

        // Consent permits plaintext, but does not turn a later lookup
        // failure into evidence that a key was removed.
        await gate.invalidate(accountID: account.id, bucket: "public")
        await keyStore.failNextLookups(1)
        let failedLookup = await manager.enqueueUpload(
            account: account, bucket: "public", key: "lookup-failed.txt",
            localURL: file, contentType: nil,
            bypassEncryption: false, requiresEncryption: destination.requiresEncryption,
            destinationHadKey: destination == .encrypted
        )
        let lookupState = await manager.awaitCompletion(id: failedLookup)
        let cause = CocoaError(.fileReadNoPermission).localizedDescription
        XCTAssertEqual(lookupState, .failed(message: String(localized: "encryption.error.lookupFailed \(cause)")))
        XCTAssertFalse(RefusingAzureStub.requested(blob: "lookup-failed.txt"))

        // An unknown preflight still requires encryption. If the next
        // lookup establishes that no key exists, it is not a removed key.
        await keyStore.failNextLookups(1)
        let unknown = await gate.keyState(accountID: account.id, bucket: "public")
        XCTAssertEqual(unknown, .unknown)
        let missingKey = await manager.enqueueUpload(
            account: account, bucket: "public", key: "no-key.txt",
            localURL: file, contentType: nil,
            bypassEncryption: false, requiresEncryption: unknown.requiresEncryption,
            destinationHadKey: unknown == .encrypted
        )
        let missingState = await manager.awaitCompletion(id: missingKey)
        XCTAssertEqual(missingState, .failed(message: String(localized: "transfer.error.destinationNoKey")))
        XCTAssertFalse(RefusingAzureStub.requested(blob: "no-key.txt"))
    }

    func testEncryptedMarkerFollowsTheKeyTheWorkerResolved() async throws {
        let keys = InMemoryEncryptionKeyStore(encryptedBuckets: [(account.id, "archive")])
        let keyStore = BlockingKeyStore(keys: keys)
        let gate = BucketEncryptionGate(keyStore: keyStore)
        let manager = try await makeManager(encryptionGate: gate)
        let file = folder.appendingPathComponent("marker.txt")
        try Data("payload".utf8).write(to: file)
        let updates = manager.taskUpdates()

        // Four workers park on the key lookup; the last two stay queued.
        var buckets: [UUID: String] = [:]
        for (index, bucket) in ["vault", "archive", "vault", "archive", "vault", "archive"].enumerated() {
            let id = await manager.enqueueUpload(account: account, bucket: bucket, key: "\(index).txt",
                                                 localURL: file, contentType: nil)
            buckets[id] = bucket
        }
        await keyStore.waitUntilHolding(4)

        var pending: [TransferTask] = []
        for await snapshot in updates {
            pending = snapshot.filter { buckets[$0.id] != nil }
            if pending.filter({ if case .running = $0.state { true } else { false } }).count == 4,
               pending.filter({ $0.state == .queued }).count == 2 { break }
        }
        for task in pending {
            XCTAssertFalse(task.isEncrypted, "\(task.key) has not resolved a key yet")
            let marker = task.encryptionMarker(bucketHasKey: true)
            XCTAssertEqual(marker, task.state == .queued ? UploadEncryptionMarker.expected : nil,
                           "\(task.key) shows no confirmed marker before its key is resolved")
        }

        // The keys change while every upload waits for its key.
        let archiveKey = try await keys.key(accountID: account.id, bucket: "archive")
        let removed = try XCTUnwrap(archiveKey)
        try await keys.delete(id: removed.id)
        _ = await keys.create(label: "Key", accountID: account.id, bucket: "vault")
        await gate.invalidate(accountID: account.id, bucket: "archive")
        await gate.invalidate(accountID: account.id, bucket: "vault")
        await keyStore.release()

        var marked: [UUID: Bool] = [:]
        for await snapshot in updates {
            for task in snapshot where buckets[task.id] != nil && task.state.isTerminal {
                marked[task.id] = task.isEncrypted
            }
            if marked.count == buckets.count { break }
        }
        for (id, bucket) in buckets {
            XCTAssertEqual(marked[id], bucket == "vault", "the key present when the worker resolved it decides")
        }
    }

    // MARK: - Helpers

    private func makeManager(encryptionGate: BucketEncryptionGate? = nil) async throws -> TransferManager {
        let keychain = InMemoryKeychain()
        try await keychain.save(
            AccountCredentials(accessKey: "teststorage", secretKey: Data(repeating: 7, count: 32).base64EncodedString()),
            for: account.id
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefusingAzureStub.self]
        let transporter = AzureBlobTransporter(
            credentialsCache: AzureCredentialsCache(keychainStore: keychain),
            session: URLSession(configuration: configuration)
        )
        return TransferManager(
            factory: S3ClientFactory(keychainStore: keychain),
            azure: transporter,
            encryptionGate: encryptionGate
        )
    }

    private func firstTerminal(of id: UUID, in stream: AsyncStream<[TransferTask]>) async -> TransferState? {
        for await snapshot in stream {
            if let state = snapshot.first(where: { $0.id == id })?.state, state.isTerminal {
                return state
            }
        }
        return nil
    }
}

private actor Flag {
    private(set) var isSet = false
    func set() { isSet = true }
}

/// Answers every Azure request with a server error and remembers the
/// requested paths.
private final class RefusingAzureStub: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var paths: [String] = []

    static func requested(blob: String) -> Bool {
        lock.withLock { paths.contains { $0.hasSuffix("/" + blob) } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        if let path = request.url?.path {
            Self.lock.withLock { Self.paths.append(path) }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1",
                                       headerFields: ["x-ms-error-code": "InternalError"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Key store whose lookups ignore cancellation and park until
/// `release()` — a worker still busy after its task was cancelled, or
/// uploads waiting for their key while the test changes `keys`.
private actor BlockingKeyStore: EncryptionKeyStoring {
    let keys: InMemoryEncryptionKeyStore
    private var held: [CheckedContinuation<Void, Never>] = []
    private var released = false

    init(keys: InMemoryEncryptionKeyStore = InMemoryEncryptionKeyStore()) {
        self.keys = keys
    }

    func waitUntilHolding(_ count: Int = 1) async {
        while held.count < count { await Task.yield() }
    }

    func release() {
        released = true
        held.forEach { $0.resume() }
        held = []
    }

    func key(accountID: UUID, bucket: String) async throws -> BucketEncryptionKey? {
        if !released { await withCheckedContinuation { held.append($0) } }
        return try await keys.key(accountID: accountID, bucket: bucket)
    }

    func all() async -> [BucketEncryptionKey] { await keys.all() }
    func create(label: String, accountID: UUID, bucket: String) async -> BucketEncryptionKey {
        await keys.create(label: label, accountID: accountID, bucket: bucket)
    }

    func copyForReassignment(_ key: BucketEncryptionKey, to accountID: UUID) async throws -> BucketEncryptionKey {
        try await keys.copyForReassignment(key, to: accountID)
    }

    func importKey(_ entry: KeyBackupEntry, replacing expectedID: UUID?) throws {
        throw CocoaError(.featureUnsupported)
    }

    func markBackupReady(id: UUID) throws {
        throw CocoaError(.featureUnsupported)
    }

    func keyMaterial(id: UUID) async throws -> Data { try await keys.keyMaterial(id: id) }
    func delete(id: UUID) async throws { try await keys.delete(id: id) }
}
