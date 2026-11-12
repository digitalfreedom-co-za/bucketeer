import XCTest
import CryptoKit
import SwiftData
import BucketeerCore

/// Exercise routing through the real transfer, preview and trash services.
/// Only the provider, credentials and keys are faked; all files are isolated.
final class EncryptionRoutingTests: XCTestCase {
    private let account = S3Account(name: "Routing", provider: .azureBlob, accountID: "teststorage")
    private let plaintext = Data([0, 255, 1, 2, 10, 13, 128])
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testUploadWithoutKeySendsPlaintext() async throws {
        let fixture = try await makeFixture(hasKey: false)
        defer { fixture.session.invalidateAndCancel() }
        let file = folder.appendingPathComponent("source")
        try plaintext.write(to: file)
        let id = await fixture.manager.enqueueUpload(account: account, bucket: fixture.bucket, key: "object",
                                                      localURL: file, contentType: nil)
        let state = await fixture.manager.awaitCompletion(id: id)
        XCTAssertEqual(state, .completed)
        XCTAssertEqual(RoutingAzureStub.uploaded(bucket: fixture.bucket), plaintext)
    }

    func testUploadWithKeySendsAnAuthenticatedEnvelope() async throws {
        let fixture = try await makeFixture(hasKey: true)
        defer { fixture.session.invalidateAndCancel() }
        let file = folder.appendingPathComponent("source")
        try plaintext.write(to: file)
        let id = await fixture.manager.enqueueUpload(account: account, bucket: fixture.bucket, key: "object",
                                                      localURL: file, contentType: nil)
        let state = await fixture.manager.awaitCompletion(id: id)
        XCTAssertEqual(state, .completed)
        let bytes = try XCTUnwrap(RoutingAzureStub.uploaded(bucket: fixture.bucket))
        XCTAssertEqual(bytes.prefix(4), Data("BCKT".utf8))
        XCTAssertTrue([UInt8(1), 2].contains(try XCTUnwrap(bytes.dropFirst(4).first)))
        XCTAssertEqual(try BucketeerEnvelope.open(envelope: bytes, key: fixture.key), plaintext)
    }

    func testEnvelopeWithoutKeyFailsWithoutPublishingCiphertext() async throws {
        let fixture = try await makeFixture(hasKey: false)
        defer { fixture.session.invalidateAndCancel() }
        let envelope = try BucketeerEnvelope.seal(plaintext: plaintext, key: fixture.key)
        RoutingAzureStub.seed(bucket: fixture.bucket, bytes: envelope, marked: true)
        for existing in [false, true] {
            let destination = folder.appendingPathComponent("download-\(existing)")
            if existing { try plaintext.write(to: destination) }
            let id = await fixture.manager.enqueueDownload(account: account, bucket: fixture.bucket, key: "object",
                                                            localURL: destination)
            let state = await fixture.manager.awaitCompletion(id: id)
            XCTAssertEqual(state, .failed(message: noKeyMessage))
            if existing {
                XCTAssertEqual(try Data(contentsOf: destination), plaintext)
            } else {
                XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            }
        }
    }

    func testPlainDownloadPassesThroughWithAndWithoutABucketKey() async throws {
        for hasKey in [false, true] {
            let fixture = try await makeFixture(hasKey: hasKey)
            defer { fixture.session.invalidateAndCancel() }
            RoutingAzureStub.seed(bucket: fixture.bucket, bytes: plaintext, marked: false)
            let destination = folder.appendingPathComponent("download-\(hasKey)")
            let id = await fixture.manager.enqueueDownload(account: account, bucket: fixture.bucket, key: "object",
                                                            localURL: destination)
            let state = await fixture.manager.awaitCompletion(id: id)
            XCTAssertEqual(state, .completed)
            XCTAssertEqual(try Data(contentsOf: destination), plaintext)
        }
    }

    func testPreviewRejectsEncryptedObjectsWithoutCachingBytes() async throws {
        for hasKey in [false, true] {
            let fixture = try await makeFixture(hasKey: hasKey)
            defer { fixture.session.invalidateAndCancel() }
            let envelope = try BucketeerEnvelope.seal(plaintext: plaintext, key: fixture.key)
            RoutingAzureStub.seed(bucket: fixture.bucket, bytes: envelope, marked: true)
            let root = folder.appendingPathComponent("preview-\(hasKey)")
            let cache = PreviewCache(downloader: fixture.downloader, encryptionGate: fixture.gate, root: root)
            let object = S3Object(key: "object", size: Int64(envelope.count), lastModified: .distantPast, etag: "etag")
            do {
                _ = try await cache.materialise(account: account, bucket: fixture.bucket, object: object)
                XCTFail("Encrypted preview must be refused")
            } catch {
                let expected = hasKey ? String(localized: "preview.error.encrypted",
                                              defaultValue: "Previews aren't available for encrypted objects. Download the object to open it.") : noKeyMessage
                XCTAssertEqual(error.localizedDescription, expected)
            }
            let cached = await cache.cachedURL(account: account, bucket: fixture.bucket, key: object.key, etag: object.etag)
            XCTAssertNil(cached)
            let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
            for case let url as URL in files.allObjects {
                XCTAssertFalse(try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
                               "Neither ciphertext nor plaintext may remain in the preview cache")
            }
        }
    }

    @MainActor
    func testTrashCaptureAndRestorePreserveTheOriginalEnvelope() async throws {
        let fixture = try await makeFixture(hasKey: true)
        defer { fixture.session.invalidateAndCancel() }
        let envelope = try BucketeerEnvelope.seal(plaintext: plaintext, key: fixture.key)
        RoutingAzureStub.seed(bucket: fixture.bucket, bytes: envelope, marked: true)
        let browser = InMemoryS3Browser()
        await browser.put(bucket: fixture.bucket, key: "object", size: Int64(envelope.count))
        let container = try ModelContainer(for: TrashRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = TrashStore(modelContainer: container, cacheRootURL: folder)
        let suite = "EncryptionRoutingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TrashSettings(defaults: defaults)
        settings.cacheEnabled = true
        let coordinator = TrashCoordinator(trashStore: store, browser: browser, transferManager: fixture.manager,
                                           cacheRootURL: folder, settings: settings)

        await coordinator.recordDeletion(account: account, bucket: fixture.bucket, keys: ["object"])
        let items = try await store.recent(limit: 10)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.cacheStatus, .cached)
        let cached = folder.appendingPathComponent(try XCTUnwrap(item.cachedFileName))
        XCTAssertEqual(try Data(contentsOf: cached), envelope, "Trash capture must bypass decryption")

        let error = await coordinator.restore(item: item, account: account)
        XCTAssertNil(error)
        XCTAssertEqual(RoutingAzureStub.uploaded(bucket: fixture.bucket), envelope,
                       "Restore must bypass encryption, preserving the original envelope byte for byte")
    }

    private var noKeyMessage: String {
        String(localized: "error.encryptedNoKey",
               defaultValue: "The object is encrypted, but no key is configured for this bucket.")
    }

    private struct Fixture {
        let bucket: String
        let key: SymmetricKey
        let gate: BucketEncryptionGate
        let manager: TransferManager
        let downloader: PreviewDownloader
        let session: URLSession
    }

    private func makeFixture(hasKey: Bool) async throws -> Fixture {
        let bucket = UUID().uuidString.lowercased()
        addTeardownBlock { RoutingAzureStub.remove(bucket: bucket) }
        let keys = InMemoryEncryptionKeyStore(encryptedBuckets: hasKey ? [(account.id, bucket)] : [])
        let key: SymmetricKey
        if let entry = try await keys.key(accountID: account.id, bucket: bucket) {
            key = try await SymmetricKey(data: keys.keyMaterial(id: entry.id))
        } else {
            key = SymmetricKey(size: .bits256)
        }
        let gate = BucketEncryptionGate(keyStore: keys)
        let keychain = InMemoryKeychain()
        try await keychain.save(AccountCredentials(accessKey: "teststorage", secretKey: Data(repeating: 7, count: 32).base64EncodedString()),
                                for: account.id)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RoutingAzureStub.self]
        let session = URLSession(configuration: configuration)
        let azure = AzureBlobTransporter(credentialsCache: AzureCredentialsCache(keychainStore: keychain), session: session)
        let factory = S3ClientFactory(keychainStore: keychain)
        return Fixture(bucket: bucket, key: key, gate: gate,
                       manager: TransferManager(factory: factory, azure: azure, encryptionGate: gate),
                       downloader: PreviewDownloader(s3Factory: factory, azureTransporter: azure), session: session)
    }
}

/// Unique bucket names isolate concurrent fixtures. Unknown requests fail locally.
private final class RoutingAzureStub: URLProtocol {
    private struct Object {
        var bytes: Data
        var marked: Bool
        var uploaded: Data?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var objects: [String: Object] = [:]

    static func seed(bucket: String, bytes: Data, marked: Bool) {
        lock.withLock { objects[bucket] = Object(bytes: bytes, marked: marked) }
    }

    static func uploaded(bucket: String) -> Data? { lock.withLock { objects[bucket]?.uploaded } }
    static func remove(bucket: String) { _ = lock.withLock { objects.removeValue(forKey: bucket) } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let body = bodyData()
        let bucket = request.url!.pathComponents.dropFirst().first ?? ""
        let (status, headers, bytes): (Int, [String: String], Data) = Self.lock.withLock {
            if request.httpMethod == "PUT" {
                Self.objects[bucket] = Object(bytes: body, marked: false, uploaded: body)
                return (201, [:], Data())
            }
            guard let object = Self.objects[bucket], ["HEAD", "GET"].contains(request.httpMethod) else {
                return (404, [:], Data())
            }
            var headers = ["Content-Length": String(object.bytes.count), "ETag": "\"etag\""]
            if object.marked { headers["x-ms-meta-" + BucketeerEnvelope.azureMetadataKey] = "1" }
            return (200, headers, request.httpMethod == "GET" ? object.bytes : Data())
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func bodyData() -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
