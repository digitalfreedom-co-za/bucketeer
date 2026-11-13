import XCTest
import CryptoKit
import SwiftData
import BucketeerCore
import SotoS3
import NIOHTTP1

/// Exercise routing through the real transfer, preview and trash services.
/// Only the provider, credentials and keys are faked; all files are isolated.
final class EncryptionRoutingTests: XCTestCase {
    private let account = S3Account(name: "Routing", provider: .azureBlob, accountID: "teststorage")
    private let s3Account = S3Account(name: "Routing S3", provider: .awsS3)
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
                                                      localURL: file, contentType: "image/png")
        let state = await fixture.manager.awaitCompletion(id: id)
        XCTAssertEqual(state, .completed)
        XCTAssertEqual(RoutingAzureStub.uploaded(bucket: fixture.bucket), plaintext)
        XCTAssertEqual(RoutingAzureStub.uploadedMarker(bucket: fixture.bucket), false)
        XCTAssertEqual(RoutingAzureStub.uploadedContentType(bucket: fixture.bucket), "image/png")
    }

    func testUploadWithKeySendsAnAuthenticatedEnvelope() async throws {
        let fixture = try await makeFixture(hasKey: true)
        defer { fixture.session.invalidateAndCancel() }
        let file = folder.appendingPathComponent("source")
        try plaintext.write(to: file)
        let id = await fixture.manager.enqueueUpload(account: account, bucket: fixture.bucket, key: "object",
                                                      localURL: file, contentType: "image/png")
        let state = await fixture.manager.awaitCompletion(id: id)
        XCTAssertEqual(state, .completed)
        XCTAssertEqual(RoutingAzureStub.uploadedContentType(bucket: fixture.bucket), "application/octet-stream",
                       "Ciphertext must not carry the plaintext's MIME type")
        let bytes = try XCTUnwrap(RoutingAzureStub.uploaded(bucket: fixture.bucket))
        XCTAssertEqual(try XCTUnwrap(bytes.dropFirst(4).first), 0x02)
        XCTAssertEqual(try BucketeerEnvelope.open(envelope: bytes, key: fixture.key), plaintext)
        XCTAssertEqual(RoutingAzureStub.uploadedMarker(bucket: fixture.bucket), true)
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
        XCTAssertEqual(RoutingAzureStub.uploadedMarker(bucket: fixture.bucket), true)
        XCTAssertEqual(RoutingAzureStub.uploadedContentType(bucket: fixture.bucket), "application/octet-stream")
    }

    func testAzureBlockListCommitStoresEnvelopesAsOctetStream() async throws {
        let fixture = try await makeFixture(hasKey: true)
        defer { fixture.session.invalidateAndCancel() }
        let file = folder.appendingPathComponent("source")
        try Data(count: Int(AzureBlobTransporter.multipartThreshold) + 1).write(to: file)
        let id = await fixture.manager.enqueueUpload(account: account, bucket: fixture.bucket, key: "object",
                                                      localURL: file, contentType: "image/png")
        let state = await fixture.manager.awaitCompletion(id: id)
        XCTAssertEqual(state, .completed)
        let commit = try XCTUnwrap(RoutingAzureStub.blockListCommit(bucket: fixture.bucket))
        XCTAssertEqual(commit.contentType, "application/xml", "The commit request itself carries the block list XML")
        XCTAssertEqual(commit.blobContentType, "application/octet-stream")
    }

    func testS3PutStoresEnvelopesAsOctetStreamAndPlaintextWithItsType() async throws {
        for hasKey in [false, true] {
            let fixture = try await makeFixture(hasKey: hasKey, account: s3Account)
            defer { fixture.session.invalidateAndCancel() }
            let file = folder.appendingPathComponent("source-\(hasKey)")
            try plaintext.write(to: file)
            let id = await fixture.manager.enqueueUpload(account: s3Account, bucket: fixture.bucket, key: "object",
                                                          localURL: file, contentType: "image/png")
            let state = await fixture.manager.awaitCompletion(id: id)
            XCTAssertEqual(state, .completed)
            let put = try XCTUnwrap(fixture.s3.requests.first { $0.method == .PUT })
            XCTAssertEqual(put.contentType, hasKey ? "application/octet-stream" : "image/png")
            XCTAssertEqual(put.marked, hasKey)
        }
    }

    /// Fresh seals skip the resumable uploader, so `S3FileUpload` initiates
    /// the multipart upload itself.
    func testS3MultipartInitiationStoresFreshEnvelopesAsOctetStream() async throws {
        let fixture = try await makeFixture(hasKey: true, account: s3Account)
        defer { fixture.session.invalidateAndCancel() }
        let file = folder.appendingPathComponent("source")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: nil))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(S3FileUpload.defaultPartSize) + 1)
        try handle.close()

        let id = await fixture.manager.enqueueUpload(account: s3Account, bucket: fixture.bucket, key: "object",
                                                      localURL: file, contentType: "image/png", bypassEncryption: false)
        let state = await fixture.manager.awaitCompletion(id: id)
        XCTAssertEqual(state, .completed)
        let requests = fixture.s3.requests
        let initiation = try XCTUnwrap(requests.first { $0.method == .POST && $0.query.keys.contains("uploads") })
        XCTAssertEqual(initiation.contentType, "application/octet-stream")
        XCTAssertTrue(initiation.marked)
        XCTAssertTrue(requests.contains { $0.method == .POST && $0.uploadID == RecordingS3HTTPClient.uploadID })
    }

    /// A restore resumed from a checkpoint initiated before envelopes were
    /// stored as octet-stream would keep the plaintext's MIME type.
    func testResumableRestoreRestartsAPreOctetStreamCheckpoint() async throws {
        let checkpoints = InMemoryCheckpointStore()
        let fixture = try await makeFixture(hasKey: true, account: s3Account, checkpointStore: checkpoints)
        defer { fixture.session.invalidateAndCancel() }
        let file = folder.appendingPathComponent("cached-envelope")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: nil))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(S3ResumableUploader.resumableThreshold))
        try handle.close()
        let size = S3ResumableUploader.resumableThreshold
        await checkpoints.upsert(MultipartUploadCheckpoint(
            accountID: s3Account.id, bucket: fixture.bucket, key: "object", localPath: file.path, fileSize: size,
            partSize: S3ResumableUploader.partSize, uploadId: "pre-fix-upload",
            fileFingerprint: MultipartUploadCheckpoint.fingerprint(for: file) + ":bucketeer-enc=1"
        ))

        let id = await fixture.manager.enqueueUpload(account: s3Account, bucket: fixture.bucket, key: "object",
                                                      localURL: file, contentType: "image/png", bypassEncryption: true)
        let state = await fixture.manager.awaitCompletion(id: id)
        XCTAssertEqual(state, .completed)
        let requests = fixture.s3.requests
        XCTAssertTrue(requests.contains { $0.method == .DELETE && $0.uploadID == "pre-fix-upload" },
                      "The stale multipart upload must be aborted")
        XCTAssertFalse(requests.contains { $0.method != .DELETE && $0.uploadID == "pre-fix-upload" })
        let initiation = try XCTUnwrap(requests.first { $0.method == .POST && $0.query.keys.contains("uploads") })
        XCTAssertEqual(initiation.contentType, "application/octet-stream")
        XCTAssertTrue(initiation.marked)
        XCTAssertTrue(requests.contains { $0.method == .POST && $0.uploadID == RecordingS3HTTPClient.uploadID })
        let remaining = await checkpoints.count
        XCTAssertEqual(remaining, 0)
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
        let s3: RecordingS3HTTPClient
    }

    private func makeFixture(hasKey: Bool, account: S3Account? = nil,
                             checkpointStore: (any CheckpointStoring)? = nil) async throws -> Fixture {
        let account = account ?? self.account
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
        let s3 = RecordingS3HTTPClient()
        let factory = S3ClientFactory(keychainStore: keychain, httpClient: s3)
        addTeardownBlock { await factory.shutdownAll() }
        let resumable = checkpointStore.map { S3ResumableUploader(factory: factory, checkpointStore: $0) }
        return Fixture(bucket: bucket, key: key, gate: gate,
                       manager: TransferManager(factory: factory, azure: azure, resumableUploader: resumable,
                                                encryptionGate: gate),
                       downloader: PreviewDownloader(s3Factory: factory, azureTransporter: azure), session: session,
                       s3: s3)
    }
}

/// Unique bucket names isolate concurrent fixtures. Unknown requests fail locally.
private final class RoutingAzureStub: URLProtocol {
    private struct Object {
        var bytes: Data
        var marked: Bool
        var uploaded: Data?
        var uploadedContentType: String?
    }

    struct BlockListCommit {
        let contentType: String?
        let blobContentType: String?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var objects: [String: Object] = [:]
    nonisolated(unsafe) private static var commits: [String: BlockListCommit] = [:]

    static func seed(bucket: String, bytes: Data, marked: Bool) {
        lock.withLock { objects[bucket] = Object(bytes: bytes, marked: marked) }
    }

    static func uploaded(bucket: String) -> Data? { lock.withLock { objects[bucket]?.uploaded } }
    static func uploadedMarker(bucket: String) -> Bool? {
        lock.withLock {
            guard let object = objects[bucket], object.uploaded != nil else { return nil }
            return object.marked
        }
    }
    static func uploadedContentType(bucket: String) -> String? {
        lock.withLock { objects[bucket]?.uploadedContentType }
    }
    static func blockListCommit(bucket: String) -> BlockListCommit? { lock.withLock { commits[bucket] } }
    static func remove(bucket: String) {
        lock.withLock {
            objects.removeValue(forKey: bucket)
            commits.removeValue(forKey: bucket)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let body = bodyData()
        let bucket = request.url!.pathComponents.dropFirst().first ?? ""
        let (status, headers, bytes): (Int, [String: String], Data) = Self.lock.withLock {
            if request.httpMethod == "PUT" {
                switch request.url?.query {
                case nil:
                    break
                case let query? where query.hasPrefix("comp=block&"):
                    return (201, [:], Data())
                case "comp=blocklist":
                    Self.commits[bucket] = BlockListCommit(
                        contentType: request.value(forHTTPHeaderField: "Content-Type"),
                        blobContentType: request.value(forHTTPHeaderField: "x-ms-blob-content-type")
                    )
                    return (201, [:], Data())
                default:
                    return (400, [:], Data())
                }
                let marked = request.value(forHTTPHeaderField: "x-ms-meta-" + BucketeerEnvelope.azureMetadataKey) == "1"
                Self.objects[bucket] = Object(bytes: body, marked: marked, uploaded: body,
                                              uploadedContentType: request.value(forHTTPHeaderField: "Content-Type"))
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

/// Answers the S3 calls of single and resumable uploads locally and
/// records what each request asked for.
private final class RecordingS3HTTPClient: AWSHTTPClient, @unchecked Sendable {
    static let uploadID = "fresh-upload"

    struct Request {
        let method: HTTPMethod
        let query: [String: String]
        let contentType: String?
        let marked: Bool
        var uploadID: String? { query["uploadId"] }
    }

    private let lock = NSLock()
    private var recorded: [Request] = []
    var requests: [Request] { lock.withLock { recorded } }

    func execute(request: AWSHTTPRequest, timeout: TimeAmount, logger: Logger) async throws -> AWSHTTPResponse {
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        let recordedRequest = Request(
            method: request.method,
            query: query,
            contentType: request.headers["Content-Type"].first,
            marked: request.headers["x-amz-meta-" + BucketeerEnvelope.s3MetadataKey].first == "1"
        )
        lock.withLock { recorded.append(recordedRequest) }
        switch (request.method, query.keys.contains("uploads"), query["uploadId"] != nil) {
        case (.POST, true, _):
            return xml("<InitiateMultipartUploadResult><UploadId>\(Self.uploadID)</UploadId></InitiateMultipartUploadResult>")
        case (.POST, _, true):
            return xml("<CompleteMultipartUploadResult><ETag>\"etag\"</ETag></CompleteMultipartUploadResult>")
        case (.GET, _, true):
            return xml("<ListPartsResult><IsTruncated>false</IsTruncated></ListPartsResult>")
        case (.DELETE, _, _):
            return AWSHTTPResponse(status: .noContent, headers: [:])
        case (.PUT, _, _):
            return AWSHTTPResponse(status: .ok, headers: ["ETag": "\"etag\""])
        default:
            return AWSHTTPResponse(status: .notFound, headers: [:])
        }
    }

    func shutdown() async throws {}

    private func xml(_ body: String) -> AWSHTTPResponse {
        AWSHTTPResponse(status: .ok, headers: ["Content-Type": "application/xml"], body: AWSHTTPBody(string: body))
    }
}

private actor InMemoryCheckpointStore: CheckpointStoring {
    private var checkpoints: [UUID: MultipartUploadCheckpoint] = [:]

    var count: Int { checkpoints.count }

    func find(accountID: UUID, bucket: String, key: String, localPath: String,
              fileSize: Int64) -> MultipartUploadCheckpoint? {
        checkpoints.values.first {
            $0.accountID == accountID && $0.bucket == bucket && $0.key == key
                && $0.localPath == localPath && $0.fileSize == fileSize
        }
    }

    func upsert(_ checkpoint: MultipartUploadCheckpoint) { checkpoints[checkpoint.id] = checkpoint }
    func delete(id: UUID) { checkpoints.removeValue(forKey: id) }
}
