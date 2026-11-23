import XCTest
import SwiftData
import BucketeerCore
import SotoS3
import NIOCore
import NIOHTTP1

/// A restore must never replace an object that took the key after the
/// delete. Runs through the real transfer queue against a local S3 fake,
/// once with the create-only header and once with the HEAD fallback.
final class TrashRestoreConflictTests: XCTestCase {
    @MainActor
    func testRestoreKeepsTheNewerObjectAndUploadsAConflictCopy() async throws {
        for provider in [S3Provider.awsS3, .wasabi] {
            let account = S3Account(name: "Restore", provider: provider)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let keychain = InMemoryKeychain()
            try await keychain.save(AccountCredentials(accessKey: "test", secretKey: "test"), for: account.id)
            let s3 = KeyedS3HTTPClient()
            let factory = S3ClientFactory(keychainStore: keychain, httpClient: s3)
            addTeardownBlock { await factory.shutdownAll() }
            let manager = TransferManager(factory: factory)
            let store = TrashStore(
                modelContainer: try ModelContainer(for: TrashRecord.self,
                                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true)),
                cacheRootURL: folder
            )
            let suite = "TrashRestoreConflictTests-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let coordinator = TrashCoordinator(trashStore: store, browser: InMemoryS3Browser(), transferManager: manager,
                                               cacheRootURL: folder, settings: TrashSettings(defaults: defaults))

            // A was deleted into the trash; B was created at the same key afterwards.
            let objectA = Data("version A".utf8)
            let objectB = Data("version B".utf8)
            let item = TrashedItem(accountID: account.id, accountName: account.name, bucket: "bucket",
                                   key: "docs/report.txt", size: Int64(objectA.count), contentType: "text/plain",
                                   etag: "a", expiresAt: Date().addingTimeInterval(3600))
            await store.record(item)
            try objectA.write(to: folder.appendingPathComponent("a.bin"))
            await store.markCached(id: item.id, fileName: "a.bin", encryptionMarked: false)
            s3.seed(path: "docs/report.txt", bytes: objectB)

            let recorded = try await store.recent(limit: 10)
            let cached = try XCTUnwrap(recorded.first)
            let outcome = await coordinator.restore(item: cached, account: account)

            guard case .restoredAsCopy(let copyKey) = outcome else {
                XCTFail("\(provider): expected a conflict copy, got \(outcome)")
                continue
            }
            XCTAssertTrue(copyKey.hasPrefix("docs/report (conflict "), "\(provider): \(copyKey)")
            XCTAssertTrue(copyKey.hasSuffix(").txt"), "\(provider): \(copyKey)")
            XCTAssertEqual(s3.object(path: "docs/report.txt"), objectB, "\(provider): the newer object must stay")
            XCTAssertEqual(s3.object(path: copyKey), objectA, "\(provider): A must come back next to it")
            let remaining = try await store.count()
            XCTAssertEqual(remaining, 0, "\(provider): the entry goes only after the restore succeeded")
        }
    }
}

/// Stores objects per key and answers PUT and HEAD like S3, including
/// the 412 for `If-None-Match: *` on an existing key.
private final class KeyedS3HTTPClient: AWSHTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var objects: [String: Data] = [:]

    func seed(path: String, bytes: Data) { lock.withLock { objects[path] = bytes } }
    func object(path: String) -> Data? { lock.withLock { objects[path] } }

    func execute(request: AWSHTTPRequest, timeout: TimeAmount, logger: Logger) async throws -> AWSHTTPResponse {
        // Path style or virtual host: the key is whatever follows the bucket.
        var path = request.url.path.drop(while: { $0 == "/" })
        if path.hasPrefix("bucket/") { path = path.dropFirst("bucket/".count) }
        let key = String(path)
        switch request.method {
        case .PUT:
            let body = try await request.body.collect(upTo: .max)
            let stored: Bool = lock.withLock {
                if request.headers["If-None-Match"].first == "*", objects[key] != nil { return false }
                objects[key] = Data(body.readableBytesView)
                return true
            }
            guard stored else {
                return AWSHTTPResponse(
                    status: .preconditionFailed,
                    headers: ["Content-Type": "application/xml"],
                    body: AWSHTTPBody(string: "<Error><Code>PreconditionFailed</Code><Message>exists</Message></Error>")
                )
            }
            return AWSHTTPResponse(status: .ok, headers: ["ETag": "\"etag\""])
        case .HEAD:
            guard let bytes = object(path: key) else { return AWSHTTPResponse(status: .notFound, headers: [:]) }
            return AWSHTTPResponse(status: .ok, headers: ["ETag": "\"etag\"", "Content-Length": String(bytes.count)])
        default:
            return AWSHTTPResponse(status: .notFound, headers: [:])
        }
    }

    func shutdown() async throws {}
}
