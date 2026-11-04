//
//  S3PinnedDownloadTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// A large object is read in ranges; every range must belong to the same
/// version, or the file would be stitched from two versions.
@Suite("S3PinnedDownload")
struct S3PinnedDownloadTests {

    private func target() throws -> (URL, URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("S3PinnedDownloadTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (folder, folder.appendingPathComponent("large.bin"))
    }

    @Test("Every range is requested for the pinned version and the parts are joined in order")
    func everyRangeIsPinned() async throws {
        let (folder, url) = try target()
        defer { try? FileManager.default.removeItem(at: folder) }
        let object = Data((0..<25).map { UInt8($0) })
        let reader = RangeReader(object: object, etag: "v1")

        try await S3PinnedDownload.download(bucket: "b", key: "large.bin", etag: "v1", size: 25,
                                            partSize: 10, to: url, reader: reader)

        #expect(await reader.requests == [
            .init(range: "bytes=0-9", ifMatch: "\"v1\""),
            .init(range: "bytes=10-19", ifMatch: "\"v1\""),
            .init(range: "bytes=20-24", ifMatch: "\"v1\"")
        ])
        #expect(try Data(contentsOf: url) == object)
    }

    @Test("An object replaced between ranges fails the download")
    func replacementBetweenRangesFails() async throws {
        let (folder, url) = try target()
        defer { try? FileManager.default.removeItem(at: folder) }
        let reader = RangeReader(object: Data(count: 25), etag: "v1", replacedAfter: 1)

        await #expect(throws: BucketeerError.preconditionFailed(key: "large.bin")) {
            try await S3PinnedDownload.download(bucket: "b", key: "large.bin", etag: "v1", size: 25,
                                                partSize: 10, to: url, reader: reader)
        }
    }
}

/// Serves byte ranges of one object; honours If-Match like S3 does.
private actor RangeReader: S3RangeReading {
    struct Request: Equatable {
        let range: String
        let ifMatch: String
    }

    private let object: Data
    private var etag: String
    private let replacedAfter: Int?
    private(set) var requests: [Request] = []

    init(object: Data, etag: String, replacedAfter: Int? = nil) {
        self.object = object
        self.etag = etag
        self.replacedAfter = replacedAfter
    }

    func read(bucket: String, key: String, versionId: String?, range: ClosedRange<Int64>,
              ifMatch: String) async throws -> Data {
        requests.append(Request(range: "bytes=\(range.lowerBound)-\(range.upperBound)", ifMatch: ifMatch))
        if requests.count - 1 == replacedAfter { etag = "v2" }
        guard ETag.matches(base: ifMatch, current: etag) else { throw BucketeerError.preconditionFailed(key: key) }
        return object.subdata(in: Int(range.lowerBound)..<Int(range.upperBound) + 1)
    }
}
