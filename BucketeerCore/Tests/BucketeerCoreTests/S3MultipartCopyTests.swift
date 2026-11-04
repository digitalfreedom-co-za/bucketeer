//
//  S3MultipartCopyTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// CopyObject stops at 5 GB (AWS); larger objects are copied in ranges.
/// The copy must be exactly the version that was asked for and must
/// not replace an object that appeared at the destination meanwhile.
@Suite("S3MultipartCopy")
struct S3MultipartCopyTests {

    private let source = S3MultipartCopy.Source(bucket: "b", key: "big.bin", etag: "v1", size: 25)

    @Test("Only objects above the single-request limit are copied in parts")
    func threshold() {
        #expect(!S3MultipartCopy.needsParts(size: 5_000_000_000, provider: .awsS3))
        #expect(S3MultipartCopy.needsParts(size: 5_000_000_001, provider: .awsS3))
        #expect(S3MultipartCopy.needsParts(size: 5_000_000_001, provider: .civo))
        // Storj copies up to about 671 GB in one request.
        #expect(!S3MultipartCopy.needsParts(size: 100_000_000_000, provider: .storj))
    }

    @Test("The parts cover the object exactly once")
    func rangesCoverTheObject() async throws {
        let copier = RecordingCopier(sourceETags: ["v1"], destinationETag: nil)

        _ = try await S3MultipartCopy.copy(source, toBucket: "b", toKey: "moved.bin", ifAbsent: true,
                                           enforced: [], copier: copier, partSize: 10)

        #expect(await copier.ranges == [0...9, 10...19, 20...24])
        #expect(await copier.completions == 1)
    }

    @Test("A source replaced during the copy aborts it")
    func changedSourceAborts() async throws {
        let copier = RecordingCopier(sourceETags: ["v2"], destinationETag: nil)

        await #expect(throws: BucketeerError.preconditionFailed(key: "moved.bin")) {
            _ = try await S3MultipartCopy.copy(source, toBucket: "b", toKey: "moved.bin", ifAbsent: false,
                                               enforced: .all, copier: copier, partSize: 10)
        }

        #expect(await copier.completions == 0)
        #expect(await copier.aborted)
    }

    @Test("An object that appeared at the destination is not replaced")
    func takenDestinationAborts() async throws {
        let copier = RecordingCopier(sourceETags: ["v1"], destinationETag: "other")

        await #expect(throws: BucketeerError.preconditionFailed(key: "moved.bin")) {
            _ = try await S3MultipartCopy.copy(source, toBucket: "b", toKey: "moved.bin", ifAbsent: true,
                                               enforced: [], copier: copier, partSize: 10)
        }

        #expect(await copier.completions == 0)
        #expect(await copier.aborted)
    }

    @Test("Where completion conditions are enforced, create-only travels as a header")
    func enforcedCreateOnlyIsSent() async throws {
        let copier = RecordingCopier(sourceETags: ["v1"], destinationETag: "other")

        _ = try await S3MultipartCopy.copy(source, toBucket: "b", toKey: "moved.bin", ifAbsent: true,
                                           enforced: .all, copier: copier, partSize: 10)

        #expect(await copier.completedIfNoneMatch == "*")
    }
}

private actor RecordingCopier: S3ObjectCopying {
    private var sourceETags: [String]
    private let destinationETag: String?
    private(set) var ranges: [ClosedRange<Int64>] = []
    private(set) var completions = 0
    private(set) var completedIfNoneMatch: String?
    private(set) var aborted = false

    init(sourceETags: [String], destinationETag: String?) {
        self.sourceETags = sourceETags
        self.destinationETag = destinationETag
    }

    func currentETag(bucket: String, key: String) async throws -> String? {
        key == "big.bin" ? sourceETags.first : destinationETag
    }

    func createMultipartCopy(of source: S3MultipartCopy.Source, toBucket: String, toKey: String) async throws -> String {
        "upload-1"
    }

    func uploadPartCopy(of source: S3MultipartCopy.Source, range: ClosedRange<Int64>, toBucket: String, toKey: String,
                        uploadID: String, partNumber: Int) async throws -> String {
        ranges.append(range)
        return "part-\(partNumber)"
    }

    func completeMultipartUpload(bucket: String, key: String, uploadID: String, parts: [S3CompletedPart],
                                 ifMatch: String?, ifNoneMatch: String?) async throws -> String? {
        completions += 1
        completedIfNoneMatch = ifNoneMatch
        return "copied"
    }

    func abortMultipartUpload(bucket: String, key: String, uploadID: String) async throws {
        aborted = true
    }
}
