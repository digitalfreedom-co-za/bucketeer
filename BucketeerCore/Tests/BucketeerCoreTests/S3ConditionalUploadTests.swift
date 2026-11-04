//
//  S3ConditionalUploadTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// Saving a large edited file must not read it into memory in one go
/// and must keep the If-Match / If-None-Match guard on the write that
/// makes it visible. In-memory object writer; files in a temp folder.
@Suite("S3ConditionalUpload")
struct S3ConditionalUploadTests {

    private func file(size: Int) throws -> (URL, URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("S3ConditionalUploadTests-\(UUID().uuidString)", isDirectory: true)
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

        let etag = try await S3ConditionalUpload.upload(
            fileAt: url, bucket: "b", key: "edited.bin", contentType: nil,
            precondition: .ifMatch("base"), writer: writer, partSize: 10
        )

        #expect(etag == "completed")
        #expect(await writer.partSizes == [10, 10, 5])
        #expect(await writer.puts == 0)
        #expect(await writer.completedIfMatch == "\"base\"")
        #expect(await writer.assembled == (try Data(contentsOf: url)))
    }

    @Test("A refused completion aborts the upload and reports the precondition")
    func refusedCompletionAborts() async throws {
        let (folder, url) = try file(size: 25)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = RecordingWriter(refusesCompletion: true)

        await #expect(throws: BucketeerError.self) {
            _ = try await S3ConditionalUpload.upload(
                fileAt: url, bucket: "b", key: "edited.bin", contentType: nil,
                precondition: .ifAbsent, writer: writer, partSize: 10
            )
        }

        #expect(await writer.aborted)
    }

    @Test("A small file goes up in one guarded PUT")
    func smallFileUsesOnePut() async throws {
        let (folder, url) = try file(size: 7)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = RecordingWriter()

        _ = try await S3ConditionalUpload.upload(
            fileAt: url, bucket: "b", key: "edited.bin", contentType: nil,
            precondition: .ifAbsent, writer: writer, partSize: 10
        )

        #expect(await writer.puts == 1)
        #expect(await writer.putIfNoneMatch == "*")
        #expect(await writer.partSizes.isEmpty)
    }
}

private actor RecordingWriter: S3ObjectWriting {
    private let refusesCompletion: Bool
    private(set) var puts = 0
    private(set) var putIfNoneMatch: String?
    private(set) var partSizes: [Int] = []
    private(set) var completedIfMatch: String?
    private(set) var aborted = false
    private var parts: [Int: Data] = [:]

    init(refusesCompletion: Bool = false) {
        self.refusesCompletion = refusesCompletion
    }

    var assembled: Data { parts.keys.sorted().reduce(into: Data()) { $0.append(parts[$1]!) } }

    func putObject(bucket: String, key: String, body: Data, contentType: String?,
                   ifMatch: String?, ifNoneMatch: String?) async throws -> String? {
        puts += 1
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
        completedIfMatch = ifMatch
        return "completed"
    }

    func abortMultipartUpload(bucket: String, key: String, uploadID: String) async throws {
        aborted = true
    }
}
