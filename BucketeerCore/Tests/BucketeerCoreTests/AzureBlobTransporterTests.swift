//
//  AzureBlobTransporterTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// Multipart transfers against a stubbed Azure endpoint: no network,
/// no Keychain, files only in a per-test temporary folder.
@Suite("AzureBlobTransporter", .serialized)
struct AzureBlobTransporterTests {

    private let account = S3Account(name: "Test", provider: .azureBlob, accountID: "teststorage")
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("AzureBlobTransporterTests-\(UUID().uuidString)", isDirectory: true)

    private func transporter() async throws -> AzureBlobTransporter {
        let keychain = StaticKeychain()
        try await keychain.save(
            AccountCredentials(accessKey: "teststorage", secretKey: Data(repeating: 7, count: 32).base64EncodedString()),
            for: account.id
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AzureStub.self]
        return AzureBlobTransporter(
            credentialsCache: AzureCredentialsCache(keychainStore: keychain),
            session: URLSession(configuration: configuration)
        )
    }

    private var multipartSize: Int { Int(AzureBlobTransporter.multipartThreshold) + 1_024 }

    @Test("Uploads of the same blob stage disjoint blocks and commit only their own")
    func uploadsUseOwnBlocks() async throws {
        AzureStub.reset(blobSize: 0)
        let transporter = try await transporter()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("large.bin")
        try Data(repeating: 1, count: multipartSize).write(to: file)

        for _ in 0..<2 {
            try await transporter.upload(account: account, container: "c", blob: "same.bin",
                                         localURL: file, contentType: nil, progress: { _, _ in })
        }

        let commits = AzureStub.committedBlockLists()
        #expect(commits.count == 2)
        let first = Set(commits[0])
        let second = Set(commits[1])
        #expect(first.isDisjoint(with: second))
        #expect(first.union(second) == Set(AzureStub.stagedBlockIDs()))
    }

    @Test("Every ranged GET is pinned to the version the HEAD reported")
    func rangesArePinnedToHeadVersion() async throws {
        AzureStub.reset(blobSize: multipartSize)
        let transporter = try await transporter()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try await transporter.download(account: account, container: "c", blob: "large.bin",
                                       localURL: folder.appendingPathComponent("large.bin"), progress: { _, _ in })

        let ranges = AzureStub.rangeRequests()
        #expect(!ranges.isEmpty)
        #expect(ranges.allSatisfy { $0.value(forHTTPHeaderField: "If-Match") == AzureStub.etag })
    }
}

/// Credentials held in memory only.
private actor StaticKeychain: KeychainStoring {
    private var items: [UUID: AccountCredentials] = [:]

    func save(_ credentials: AccountCredentials, for accountID: UUID) async throws {
        items[accountID] = credentials
    }

    func load(for accountID: UUID) async throws -> AccountCredentials {
        guard let credentials = items[accountID] else { throw BucketeerError.authenticationFailed }
        return credentials
    }

    func delete(for accountID: UUID) async throws {
        items[accountID] = nil
    }
}

/// Answers HEAD, ranged GET, Put Block and Put Block List like Azure
/// would and records what it was sent.
private final class AzureStub: URLProtocol {
    static let etag = "\"0x8DC0FFEE\""

    private struct State {
        var blobSize = 0
        var requests: [URLRequest] = []
        var committed: [[String]] = []
    }

    nonisolated(unsafe) private static var state = State()
    private static let lock = NSLock()

    static func reset(blobSize: Int) {
        lock.withLock { state = State(blobSize: blobSize) }
    }

    static func committedBlockLists() -> [[String]] {
        lock.withLock { state.committed }
    }

    static func stagedBlockIDs() -> [String] {
        lock.withLock { state.requests.compactMap { query($0)["blockid"] } }
    }

    static func rangeRequests() -> [URLRequest] {
        lock.withLock { state.requests.filter { $0.value(forHTTPHeaderField: "Range") != nil } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let body = Self.bodyData(of: request)
        let (status, headers, payload) = Self.lock.withLock { () -> (Int, [String: String], Data) in
            Self.state.requests.append(request)
            return Self.respond(to: request, body: body)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// Called with the lock held.
    private static func respond(to request: URLRequest, body: Data) -> (Int, [String: String], Data) {
        let size = state.blobSize
        switch (request.httpMethod, query(request)["comp"]) {
        case ("HEAD", _):
            return (200, ["Content-Length": String(size), "ETag": etag], Data())
        case ("GET", _):
            guard let range = request.value(forHTTPHeaderField: "Range"),
                  let bounds = parse(range: range)
            else { return (200, ["ETag": etag], Data(repeating: 2, count: size)) }
            let length = bounds.upperBound - bounds.lowerBound + 1
            return (206, ["ETag": etag], Data(repeating: 2, count: length))
        case ("PUT", "blocklist"):
            state.committed.append(latestIDs(in: body))
            return (201, ["ETag": etag], Data())
        case ("PUT", _):
            return (201, [:], Data())
        default:
            return (400, [:], Data())
        }
    }

    private static func query(_ request: URLRequest) -> [String: String] {
        let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }

    private static func parse(range: String) -> ClosedRange<Int>? {
        let parts = range.replacingOccurrences(of: "bytes=", with: "").split(separator: "-")
        guard parts.count == 2, let low = Int(parts[0]), let high = Int(parts[1]) else { return nil }
        return low...high
    }

    private static func latestIDs(in body: Data) -> [String] {
        let xml = String(decoding: body, as: UTF8.self)
        return xml.components(separatedBy: "<Latest>").dropFirst().compactMap {
            $0.components(separatedBy: "</Latest>").first
        }
    }

    private static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
