//
//  S3FileUploadTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// Uploading a large file must not read it into memory in one go and
/// must keep the If-Match / If-None-Match guard on the write that makes
/// it visible. In-memory object writer; files in a temp folder.
@Suite("S3FileUpload")
struct S3FileUploadTests {

    private let enforcing: S3Provider.ConditionalRequests = [.writeIfMatch, .writeIfAbsent, .completionConditions]

    private func file(size: Int) throws -> (URL, URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("S3FileUploadTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("edited.bin")
        try Data((0..<size).map { UInt8($0 % 251) }).write(to: url)
        return (folder, url)
    }

    @Test("A file above the part size goes up in bounded parts, guarded at completion")
    func largeFileStreamsInParts() async throws {
        let (folder, url) = try file(size: 25)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = RecordingWriter()

        let etag = try await S3FileUpload.upload(
            fileAt: url, bucket: "b", key: "edited.bin", contentType: nil,
            precondition: .ifMatch("base"), enforced: enforcing, writer: writer, partSize: 10
        )

        #expect(etag == "completed")
        #expect(await writer.partSizes == [10, 10, 5])
        #expect(await writer.puts == 0)
        #expect(await writer.completedIfMatch == "\"base\"")
        #expect(await writer.assembled == (try Data(contentsOf: url)))
    }

    @Test("A file that would need more than 10,000 parts goes up in larger parts")
    func partSizeGrowsToStayWithinPartLimit() async throws {
        let (folder, url) = try file(size: 20_001)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = RecordingWriter()

        _ = try await S3FileUpload.upload(
            fileAt: url, bucket: "b", key: "edited.bin", contentType: nil,
            precondition: .ifAbsent, enforced: enforcing, writer: writer, partSize: 1
        )

        #expect(await writer.partSizes.count <= 10_000)
        #expect(await writer.assembled == (try Data(contentsOf: url)))
    }

    @Test("A refused completion aborts the upload and reports the precondition")
    func refusedCompletionAborts() async throws {
        let (folder, url) = try file(size: 25)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = RecordingWriter(refusesCompletion: true)

        await #expect(throws: BucketeerError.self) {
            _ = try await S3FileUpload.upload(
                fileAt: url, bucket: "b", key: "edited.bin", contentType: nil,
                precondition: .ifAbsent, enforced: enforcing, writer: writer, partSize: 10
            )
        }

        #expect(await writer.aborted)
    }

    @Test("A small file goes up in one guarded PUT")
    func smallFileUsesOnePut() async throws {
        let (folder, url) = try file(size: 7)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = RecordingWriter()

        _ = try await S3FileUpload.upload(
            fileAt: url, bucket: "b", key: "edited.bin", contentType: nil,
            precondition: .ifAbsent, enforced: enforcing, writer: writer, partSize: 10
        )

        #expect(await writer.puts == 1)
        #expect(await writer.putIfNoneMatch == "*")
        #expect(await writer.partSizes.isEmpty)
    }

    // MARK: - Providers that do not enforce the condition

    @Test("Without If-Match support the base is compared just before an unguarded PUT")
    func unenforcedIfMatchIsCheckedBeforeThePut() async throws {
        let (folder, url) = try file(size: 7)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = RecordingWriter(currentETag: "\"base\"")

        _ = try await S3FileUpload.upload(
            fileAt: url, bucket: "b", key: "edited.bin", contentType: nil,
            precondition: .ifMatch("base"), enforced: [], writer: writer, partSize: 10
        )

        #expect(await writer.puts == 1)
        #expect(await writer.putIfMatch == nil)
        #expect(await writer.putIfNoneMatch == nil)
    }

    @Test("Without If-Match support a changed object is refused and nothing is written")
    func unenforcedIfMatchRefusesAChangedObject() async throws {
        let (folder, url) = try file(size: 7)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = RecordingWriter(currentETag: "newer")

        await #expect(throws: BucketeerError.preconditionFailed(key: "edited.bin")) {
            _ = try await S3FileUpload.upload(
                fileAt: url, bucket: "b", key: "edited.bin", contentType: nil,
                precondition: .ifMatch("base"), enforced: [], writer: writer, partSize: 10
            )
        }

        #expect(await writer.puts == 0)
    }

    @Test("Without create-only support an existing object stops the multipart upload before completion")
    func unenforcedIfAbsentAbortsBeforeCompletion() async throws {
        let (folder, url) = try file(size: 25)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = RecordingWriter(currentETag: "someone-elses")

        await #expect(throws: BucketeerError.preconditionFailed(key: "edited.bin")) {
            _ = try await S3FileUpload.upload(
                fileAt: url, bucket: "b", key: "edited.bin", contentType: nil,
                precondition: .ifAbsent, enforced: [], writer: writer, partSize: 10
            )
        }

        #expect(await writer.completions == 0)
        #expect(await writer.aborted)
    }

    @Test("Without create-only support a free key gets an unguarded completion")
    func unenforcedIfAbsentCompletesAFreeKey() async throws {
        let (folder, url) = try file(size: 25)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = RecordingWriter(currentETag: nil)

        _ = try await S3FileUpload.upload(
            fileAt: url, bucket: "b", key: "edited.bin", contentType: nil,
            precondition: .ifAbsent, enforced: [.writeIfMatch], writer: writer, partSize: 10
        )

        #expect(await writer.completions == 1)
        #expect(await writer.completedIfNoneMatch == nil)
    }

    @Test("Without a precondition parts go up as plain bodies, nothing is checked or sent")
    func unconditionalUploadStreamsParts() async throws {
        let (folder, url) = try file(size: 25)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = RecordingWriter(currentETag: "anything")

        _ = try await S3FileUpload.upload(
            fileAt: url, bucket: "b", key: "edited.bin", contentType: nil,
            precondition: nil, enforced: [], writer: writer, partSize: 10
        )

        #expect(await writer.partSizes == [10, 10, 5])
        #expect(await writer.lookups == 0)
        #expect(await writer.completedIfMatch == nil)
        #expect(await writer.completedIfNoneMatch == nil)
    }

    @Test("Part size grows to stay within 10,000 parts and never drops below the preferred size")
    func partSizeRule() {
        let preferred = 8 * 1024 * 1024
        #expect(S3FileUpload.partSize(forFileOf: 100 * 1024 * 1024, preferred: preferred) == preferred)
        let huge: Int64 = 200 * 1024 * 1024 * 1024
        let size = S3FileUpload.partSize(forFileOf: huge, preferred: preferred)
        #expect(Int64(size) * 10_000 >= huge)
        #expect(size > preferred)
    }

    @Test("Conditions enforced only on PutObject are checked before an unguarded multipart completion")
    func putOnlyConditionsAreCheckedBeforeCompletion() async throws {
        let (folder, url) = try file(size: 25)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = RecordingWriter(currentETag: "newer")

        await #expect(throws: BucketeerError.preconditionFailed(key: "edited.bin")) {
            _ = try await S3FileUpload.upload(
                fileAt: url, bucket: "b", key: "edited.bin", contentType: nil,
                precondition: .ifMatch("base"), enforced: [.writeIfMatch, .writeIfAbsent], writer: writer, partSize: 10
            )
        }

        #expect(await writer.completions == 0)
        #expect(await writer.aborted)
    }
}

private actor RecordingWriter: S3ObjectWriting {
    private let refusesCompletion: Bool
    private let currentETag: String?
    private(set) var puts = 0
    private(set) var putIfMatch: String?
    private(set) var putIfNoneMatch: String?
    private(set) var partSizes: [Int] = []
    private(set) var completions = 0
    private(set) var completedIfMatch: String?
    private(set) var completedIfNoneMatch: String?
    private(set) var aborted = false
    private var parts: [Int: Data] = [:]

    init(refusesCompletion: Bool = false, currentETag: String? = nil) {
        self.refusesCompletion = refusesCompletion
        self.currentETag = currentETag
    }

    private(set) var lookups = 0

    func currentETag(bucket: String, key: String) async throws -> String? {
        lookups += 1
        return currentETag
    }

    var assembled: Data { parts.keys.sorted().reduce(into: Data()) { $0.append(parts[$1]!) } }

    func putObject(bucket: String, key: String, body: Data, contentType: String?,
                   ifMatch: String?, ifNoneMatch: String?) async throws -> String? {
        puts += 1
        putIfMatch = ifMatch
        putIfNoneMatch = ifNoneMatch
        return "put"
    }

    func createMultipartUpload(bucket: String, key: String, contentType: String?) async throws -> String {
        "upload-1"
    }

    func uploadPart(bucket: String, key: String, uploadID: String, partNumber: Int, body: Data) async throws -> String {
        partSizes.append(body.count)
        parts[partNumber] = body
        return "part-\(partNumber)"
    }

    func completeMultipartUpload(bucket: String, key: String, uploadID: String, parts: [S3CompletedPart],
                                 ifMatch: String?, ifNoneMatch: String?) async throws -> String? {
        if refusesCompletion { throw BucketeerError.preconditionFailed(key: key) }
        completions += 1
        completedIfMatch = ifMatch
        completedIfNoneMatch = ifNoneMatch
        return "completed"
    }

    func abortMultipartUpload(bucket: String, key: String, uploadID: String) async throws {
        aborted = true
    }
}
