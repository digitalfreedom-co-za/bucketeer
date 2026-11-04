//
//  S3MultipartCopyTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import Testing
@preconcurrency import SotoS3
@testable import BucketeerCore

/// CopyObject stops at 5 GB (AWS); larger objects are copied in ranges.
/// The copy must be exactly the version that was asked for — every
/// range pinned to it — and must not replace an object that appeared
/// at the destination meanwhile.
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
        let copier = SimulatedProvider(history: ["v1"])

        _ = try await S3MultipartCopy.copy(source, toBucket: "b", toKey: "moved.bin", precondition: .ifAbsent,
                                           provider: .awsS3, copier: copier, partSize: 10)

        #expect(await copier.ranges == [0...9, 10...19, 20...24])
        #expect(await copier.completions == 1)
    }

    @Test("A source replaced and restored during the copy (A → B → A) is never mixed into the copy")
    func sourceChangedBetweenPartsAborts() async throws {
        // The source is B only while part 2 is copied; the final HEAD
        // would see A again.
        for provider in [S3Provider.awsS3, .digitalOceanSpaces, .civo, .cloudflareR2] {
            let copier = SimulatedProvider(history: ["v1", "v2", "v1"])

            await #expect(throws: BucketeerError.preconditionFailed(key: "moved.bin")) {
                _ = try await S3MultipartCopy.copy(source, toBucket: "b", toKey: "moved.bin", precondition: nil,
                                                   provider: provider, copier: copier, partSize: 10)
            }

            #expect(await copier.completions == 0)
            #expect(await copier.aborted)
        }
    }

    @Test("A metadata edit does not overwrite an object replaced after the last part")
    func editedObjectReplacedBeforeCompletionIsKept() async throws {
        // AWS enforces If-Match on completion; Civo is checked with a HEAD.
        for provider in [S3Provider.awsS3, .civo] {
            let copier = SimulatedProvider(history: ["v1"], replacedAfterParts: "v2")
            var edit = source
            edit.replacement = ObjectMetadata(contentType: "text/plain")

            await #expect(throws: BucketeerError.preconditionFailed(key: "big.bin")) {
                _ = try await S3MultipartCopy.copy(edit, toBucket: "b", toKey: "big.bin",
                                                   precondition: .ifMatch("v1"), provider: provider,
                                                   copier: copier, partSize: 10)
            }

            #expect(await copier.completions == 0)
            #expect(await copier.aborted)
        }
    }

    @Test("Restoring a noncurrent null version copies that version, not the current one")
    func noncurrentNullVersionIsRestored() async throws {
        // AWS: copy-source condition per part; Civo: relayed reads.
        for provider in [S3Provider.awsS3, .civo] {
            let copier = SimulatedProvider(history: ["v2"], nullVersion: "v1")
            var restore = source
            restore.versionId = "null"

            _ = try await S3MultipartCopy.copy(restore, toBucket: "b", toKey: "big.bin", precondition: nil,
                                               provider: provider, copier: copier, partSize: 10)

            #expect(await copier.partVersions == ["null", "null", "null"])
            #expect(await copier.completions == 1)
        }
    }

    @Test("A null version beneath a delete marker can be restored")
    func nullVersionBeneathDeleteMarkerIsRestored() async throws {
        for provider in [S3Provider.awsS3, .civo] {
            let copier = SimulatedProvider(history: [nil], nullVersion: "v1")
            var restore = source
            restore.versionId = "null"

            _ = try await S3MultipartCopy.copy(restore, toBucket: "b", toKey: "big.bin", precondition: nil,
                                               provider: provider, copier: copier, partSize: 10)

            #expect(await copier.completions == 1)
        }
    }

    @Test("The copy takes its properties from the HEAD that proved the ETag, not from a later read")
    func propertiesComeFromTheETagHead() async throws {
        // A's HEAD established the source. The copier offers no way to
        // read the properties again, so a B visible later cannot leak in.
        let headA = S3.HeadObjectOutput(contentLength: 25, contentType: "video/mp4", eTag: "\"v1\"",
                                        metadata: ["owner": "a"], versionId: "null")
        let source = S3MultipartCopy.Source(bucket: "b", key: "big.bin", head: headA)
        let copier = SimulatedProvider(history: ["v1"])

        _ = try await S3MultipartCopy.copy(source, toBucket: "b", toKey: "moved.bin", precondition: nil,
                                           provider: .awsS3, copier: copier, partSize: 10)

        #expect(source.etag == "v1")
        #expect(source.size == 25)
        let request = try #require(await copier.createRequest)
        #expect(request.contentType == "video/mp4")
        #expect(request.metadata == ["owner": "a"])
    }

    @Test("A known source version pins every part, whatever the provider's conditions")
    func versionPinsEveryPart() async throws {
        let copier = SimulatedProvider(history: ["v1", "v2", "v1"])
        var pinned = source
        pinned.versionId = "3HL4kqtJ"

        _ = try await S3MultipartCopy.copy(pinned, toBucket: "b", toKey: "moved.bin", precondition: nil,
                                           provider: .backblazeB2, copier: copier, partSize: 10)

        #expect(await copier.partVersions == ["3HL4kqtJ", "3HL4kqtJ", "3HL4kqtJ"])
        #expect(await copier.completions == 1)
    }

    @Test("Where parts cannot be pinned the copy is refused before anything is written")
    func unpinnableCopyIsRefused() async throws {
        // B2, Wasabi, custom: no part conditions, no known GET If-Match.
        // Storj: UploadPartCopy only on request.
        for provider in [S3Provider.backblazeB2, .wasabi, .custom, .storj] {
            let copier = SimulatedProvider(history: ["v1"])

            await #expect(throws: BucketeerError.largeCopyUnsupported(key: "big.bin")) {
                _ = try await S3MultipartCopy.copy(source, toBucket: "b", toKey: "moved.bin", precondition: nil,
                                                   provider: provider, copier: copier, partSize: 10)
            }

            #expect(await copier.uploadsStarted == 0)
        }
    }

    @Test("Without UploadPartCopy the bytes are relayed, every range read with If-Match")
    func relayReadsPinnedRanges() async throws {
        let copier = SimulatedProvider(history: ["v1"])

        _ = try await S3MultipartCopy.copy(source, toBucket: "b", toKey: "moved.bin", precondition: nil,
                                           provider: .civo, copier: copier, partSize: 10)

        #expect(await copier.readConditions == ["\"v1\"", "\"v1\"", "\"v1\""])
        #expect(await copier.uploadedBytes == 25)
        #expect(await copier.partCopies == 0)
    }

    @Test("An object that appeared at the destination is not replaced")
    func takenDestinationAborts() async throws {
        let copier = SimulatedProvider(history: ["v1"], destinationETag: "other")

        await #expect(throws: BucketeerError.preconditionFailed(key: "moved.bin")) {
            _ = try await S3MultipartCopy.copy(source, toBucket: "b", toKey: "moved.bin", precondition: .ifAbsent,
                                               provider: .civo, copier: copier, partSize: 10)
        }

        #expect(await copier.completions == 0)
        #expect(await copier.aborted)
    }

    @Test("Where completion conditions are enforced, create-only travels as a header")
    func enforcedCreateOnlyIsSent() async throws {
        let copier = SimulatedProvider(history: ["v1"], destinationETag: "other")

        _ = try await S3MultipartCopy.copy(source, toBucket: "b", toKey: "moved.bin", precondition: .ifAbsent,
                                           provider: .awsS3, copier: copier, partSize: 10)

        #expect(await copier.completedIfNoneMatch == "*")
    }

    // MARK: - CreateMultipartUpload request

    private let headed = S3MultipartCopy.Source(bucket: "b", key: "big.bin", head: S3.HeadObjectOutput(
        cacheControl: "max-age=60", contentDisposition: "attachment", contentEncoding: "gzip",
        contentLanguage: "de", contentLength: 25, contentType: "video/mp4", eTag: "\"v1\"",
        expires: "Wed, 21 Oct 2026 07:28:00 GMT", metadata: ["owner": "marcel"], storageClass: .standardIa,
        websiteRedirectLocation: "/other"
    ))

    @Test("The copy keeps the source's headers, metadata and tags")
    func requestKeepsProperties() {
        let request = S3MultipartCopy.createRequest(
            for: headed, tags: ["project": "a b", "team": "x&y"], toBucket: "dest", toKey: "moved.bin"
        )

        #expect(request.bucket == "dest")
        #expect(request.key == "moved.bin")
        #expect(request.cacheControl == "max-age=60")
        #expect(request.contentDisposition == "attachment")
        #expect(request.contentEncoding == "gzip")
        #expect(request.contentLanguage == "de")
        #expect(request.contentType == "video/mp4")
        #expect(request.expires == "Wed, 21 Oct 2026 07:28:00 GMT")
        #expect(request.metadata == ["owner": "marcel"])
        #expect(request.storageClass == .standardIa)
        #expect(request.websiteRedirectLocation == "/other")
        #expect(request.tagging == "project=a%20b&team=x%26y")
    }

    @Test("Providers without tagging get no tagging header")
    func requestWithoutTags() {
        let request = S3MultipartCopy.createRequest(for: headed, tags: nil, toBucket: "b", toKey: "k")

        #expect(request.tagging == nil)
    }

    @Test("A metadata edit replaces the properties instead of copying them")
    func requestWithReplacement() {
        var edit = headed
        edit.replacement = ObjectMetadata(contentType: "text/plain", cacheControl: "no-cache",
                                          userMetadata: ["a": "1"], storageClass: "STANDARD_IA")

        let request = S3MultipartCopy.createRequest(for: edit, tags: ["k": "v"], toBucket: "b", toKey: "k")

        #expect(request.contentType == "text/plain")
        #expect(request.cacheControl == "no-cache")
        #expect(request.contentDisposition == nil)
        #expect(request.contentLanguage == nil)
        #expect(request.metadata == ["a": "1"])
        #expect(request.storageClass == .standardIa)
        #expect(request.tagging == "k=v")
    }
}

/// A provider whose source object goes through `history`, one ETag per
/// range (`nil`: a delete marker is current). A `"null"` version selector
/// reads `nullVersion` instead. It honours a part's copy-source condition,
/// a range read's If-Match and If-Match on completion; without them it
/// copies whatever is selected.
private actor SimulatedProvider: S3ObjectCopying {
    private let history: [String?]
    private let nullVersion: String?
    private let replacedAfterParts: String?
    private let destinationETag: String?
    private var rangeIndex = 0
    private(set) var ranges: [ClosedRange<Int64>] = []
    private(set) var partVersions: [String?] = []
    private(set) var readConditions: [String] = []
    private(set) var partCopies = 0
    private(set) var uploadedBytes = 0
    private(set) var uploadsStarted = 0
    private(set) var createRequest: S3.CreateMultipartUploadRequest?
    private(set) var completions = 0
    private(set) var completedIfNoneMatch: String?
    private(set) var aborted = false

    init(history: [String?], nullVersion: String? = nil, replacedAfterParts: String? = nil,
         destinationETag: String? = nil) {
        self.history = history
        self.nullVersion = nullVersion
        self.replacedAfterParts = replacedAfterParts
        self.destinationETag = destinationETag
    }

    private func sourceETag(versionId: String?) throws -> String {
        let current = history[min(rangeIndex, history.count - 1)]
        rangeIndex += 1
        if versionId == "null", let nullVersion { return nullVersion }
        guard let current else { throw BucketeerError.objectNotFound(key: "big.bin") }
        return current
    }

    func currentETag(bucket: String, key: String) async throws -> String? {
        guard key == "big.bin" else { return destinationETag }
        return replacedAfterParts ?? history.last.flatMap { $0 }
    }

    func tags(of source: S3MultipartCopy.Source) async throws -> [String: String] {
        [:]
    }

    func createMultipartCopy(_ request: S3.CreateMultipartUploadRequest) async throws -> String {
        uploadsStarted += 1
        createRequest = request
        return "upload-1"
    }

    func uploadPartCopy(of source: S3MultipartCopy.Source, range: ClosedRange<Int64>, toBucket: String, toKey: String,
                        uploadID: String, partNumber: Int, sourceIfMatch: String?) async throws -> String {
        let selected = try sourceETag(versionId: source.versionId)
        partCopies += 1
        ranges.append(range)
        partVersions.append(source.versionId)
        if let sourceIfMatch, ETag.normalized(sourceIfMatch) != selected {
            throw BucketeerError.preconditionFailed(key: toKey)
        }
        return "part-\(partNumber)"
    }

    func read(bucket: String, key: String, versionId: String?, range: ClosedRange<Int64>,
              ifMatch: String) async throws -> Data {
        let selected = try sourceETag(versionId: versionId)
        readConditions.append(ifMatch)
        ranges.append(range)
        partVersions.append(versionId)
        guard ETag.normalized(ifMatch) == selected else { throw BucketeerError.preconditionFailed(key: key) }
        return Data(count: range.count)
    }

    func uploadPart(bucket: String, key: String, uploadID: String, partNumber: Int, body: Data) async throws -> String {
        uploadedBytes += body.count
        return "part-\(partNumber)"
    }

    func completeMultipartUpload(bucket: String, key: String, uploadID: String, parts: [S3CompletedPart],
                                 ifMatch: String?, ifNoneMatch: String?) async throws -> String? {
        if let ifMatch, try await ETag.normalized(ifMatch) != currentETag(bucket: bucket, key: key) {
            throw BucketeerError.preconditionFailed(key: key)
        }
        completions += 1
        completedIfNoneMatch = ifNoneMatch
        return "copied"
    }

    func abortMultipartUpload(bucket: String, key: String, uploadID: String) async throws {
        aborted = true
    }
}
