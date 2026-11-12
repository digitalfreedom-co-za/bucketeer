//
//  S3FileUpload.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
@preconcurrency import SotoS3
@preconcurrency import NIOCore

/// One uploaded part of a multipart upload.
public struct S3CompletedPart: Sendable, Equatable {
    public let number: Int
    public let etag: String
}

/// The S3 writes a file upload needs; `SotoObjectWriter` is the
/// production implementation. Precondition refusals surface as
/// `BucketeerError.preconditionFailed`.
public protocol S3ObjectWriting: Sendable {
    /// The object's ETag, or `nil` when there is none.
    func currentETag(bucket: String, key: String) async throws -> String?
    func putObject(bucket: String, key: String, body: Data, contentType: String?,
                   ifMatch: String?, ifNoneMatch: String?) async throws -> String?
    func createMultipartUpload(bucket: String, key: String, contentType: String?) async throws -> String
    func uploadPart(bucket: String, key: String, uploadID: String, partNumber: Int, body: Data) async throws -> String
    func completeMultipartUpload(bucket: String, key: String, uploadID: String, parts: [S3CompletedPart],
                                 ifMatch: String?, ifNoneMatch: String?) async throws -> String?
    func abortMultipartUpload(bucket: String, key: String, uploadID: String) async throws
}

/// Uploads a file, optionally under a write precondition (If-Match /
/// If-None-Match), without holding it in memory: small files in one
/// PUT, larger ones as a multipart upload read part by part, with the
/// precondition on the completion — the request that makes the new
/// version visible. A refused or failed upload is aborted so no parts
/// linger. A condition the provider does not enforce (`enforced`) is
/// checked with a HEAD right before that request and not sent.
///
/// Every body is a complete buffer, so requests carry a plain signed
/// payload: Soto streams its own multipart parts as `aws-chunked`,
/// which Civo rejects and the other providers do not document.
public enum S3FileUpload {

    public static let defaultPartSize = 8 * 1024 * 1024
    public static let maximumPartCount = 10_000

    /// `preferred`, or larger where the file would otherwise need more
    /// than `maximumPartCount` parts.
    public static func partSize(forFileOf size: Int64, preferred: Int = defaultPartSize) -> Int {
        max(preferred, Int((size + Int64(maximumPartCount) - 1) / Int64(maximumPartCount)))
    }

    /// Returns the ETag the write answered with (unquoted).
    public static func upload(
        fileAt url: URL,
        bucket: String,
        key: String,
        contentType: String?,
        precondition: WritePrecondition?,
        enforced: S3Provider.ConditionalRequests,
        writer: any S3ObjectWriting,
        partSize: Int = defaultPartSize,
        progress: @Sendable (Int64) async -> Void = { _ in }
    ) async throws -> String? {
        let size = try fileSize(of: url)
        let putHeaders = S3Service.headers(for: precondition, enforced: enforced)
        if size <= Int64(partSize) {
            let body = try Data(contentsOf: url)
            try await verifyUnlessSent(precondition, headers: putHeaders, bucket: bucket, key: key, writer: writer)
            let etag = try await writer.putObject(bucket: bucket, key: key, body: body, contentType: contentType,
                                                  ifMatch: putHeaders.ifMatch, ifNoneMatch: putHeaders.ifNoneMatch)
            await progress(size)
            return etag.map(ETag.normalized)
        }
        // Larger parts instead of a failure after gigabytes were sent.
        let partSize = Self.partSize(forFileOf: size, preferred: partSize)
        let uploadID = try await writer.createMultipartUpload(bucket: bucket, key: key, contentType: contentType)
        do {
            let parts = try await uploadParts(of: url, size: size, partSize: partSize, bucket: bucket, key: key,
                                              uploadID: uploadID, writer: writer, progress: progress)
            let headers = enforced.contains(.completionConditions)
                ? putHeaders
                : S3Service.headers(for: nil, enforced: [])
            try await verifyUnlessSent(precondition, headers: headers, bucket: bucket, key: key, writer: writer)
            let etag = try await writer.completeMultipartUpload(
                bucket: bucket, key: key, uploadID: uploadID, parts: parts,
                ifMatch: headers.ifMatch, ifNoneMatch: headers.ifNoneMatch
            )
            return etag.map(ETag.normalized)
        } catch {
            try? await writer.abortMultipartUpload(bucket: bucket, key: key, uploadID: uploadID)
            throw error
        }
    }

    /// Checks the precondition with a HEAD when no header carries it.
    private static func verifyUnlessSent(
        _ precondition: WritePrecondition?,
        headers: (ifMatch: String?, ifNoneMatch: String?),
        bucket: String,
        key: String,
        writer: any S3ObjectWriting
    ) async throws {
        guard let precondition, headers.ifMatch == nil, headers.ifNoneMatch == nil else { return }
        let current = try await writer.currentETag(bucket: bucket, key: key)
        try PreconditionCheck.verify(precondition, current: current, key: key)
    }

    private static func uploadParts(
        of url: URL,
        size: Int64,
        partSize: Int,
        bucket: String,
        key: String,
        uploadID: String,
        writer: any S3ObjectWriting,
        progress: @Sendable (Int64) async -> Void
    ) async throws -> [S3CompletedPart] {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw BucketeerError.sandboxAccessDenied(url)
        }
        defer { try? handle.close() }
        var parts: [S3CompletedPart] = []
        var sent: Int64 = 0
        while sent < size {
            try Task.checkCancellation()
            let length = Int(min(Int64(partSize), size - sent))
            // A short read means the file changed size under us; the
            // completed object would not be the file that was saved.
            guard let chunk = try handle.read(upToCount: length), chunk.count == length else {
                throw BucketeerError.sandboxAccessDenied(url)
            }
            let number = parts.count + 1
            let etag = try await writer.uploadPart(bucket: bucket, key: key, uploadID: uploadID,
                                                   partNumber: number, body: chunk)
            parts.append(S3CompletedPart(number: number, etag: etag))
            sent += Int64(length)
            await progress(sent)
        }
        return parts
    }

    private static func fileSize(of url: URL) throws -> Int64 {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw BucketeerError.sandboxAccessDenied(url)
        }
        return Int64(size)
    }
}

/// `S3ObjectWriting` on a Soto `S3` client.
public struct SotoObjectWriter: S3ObjectWriting {
    let s3: S3

    private let metadata: [String: String]?

    public init(s3: S3, metadata: [String: String]? = nil) {
        self.s3 = s3
        self.metadata = metadata
    }

    public func currentETag(bucket: String, key: String) async throws -> String? {
        try await S3Service.currentETag(s3: s3, bucket: bucket, key: key)
    }

    public func putObject(bucket: String, key: String, body: Data, contentType: String?,
                          ifMatch: String?, ifNoneMatch: String?) async throws -> String? {
        try await mapped(key: key) {
            try await s3.putObject(.init(
                body: AWSHTTPBody(buffer: ByteBuffer(bytes: body)),
                bucket: bucket, contentType: contentType,
                ifMatch: ifMatch, ifNoneMatch: ifNoneMatch, key: key, metadata: metadata
            )).eTag
        }
    }

    public func createMultipartUpload(bucket: String, key: String, contentType: String?) async throws -> String {
        try await mapped(key: key) {
            let output = try await s3.createMultipartUpload(.init(bucket: bucket, contentType: contentType, key: key, metadata: metadata))
            guard let uploadID = output.uploadId else {
                throw BucketeerError.providerError(statusCode: 0, message: "The provider returned no multipart upload ID.")
            }
            return uploadID
        }
    }

    public func uploadPart(bucket: String, key: String, uploadID: String, partNumber: Int, body: Data) async throws -> String {
        try await mapped(key: key) {
            let output = try await s3.uploadPart(.init(
                body: AWSHTTPBody(buffer: ByteBuffer(bytes: body)),
                bucket: bucket, key: key, partNumber: partNumber, uploadId: uploadID
            ))
            guard let etag = output.eTag else {
                throw BucketeerError.providerError(statusCode: 0, message: "The provider returned no ETag for part \(partNumber).")
            }
            return etag
        }
    }

    public func completeMultipartUpload(bucket: String, key: String, uploadID: String, parts: [S3CompletedPart],
                                        ifMatch: String?, ifNoneMatch: String?) async throws -> String? {
        try await mapped(key: key) {
            try await s3.completeMultipartUpload(.init(
                bucket: bucket, ifMatch: ifMatch, ifNoneMatch: ifNoneMatch, key: key,
                multipartUpload: .init(parts: parts.map { .init(eTag: $0.etag, partNumber: $0.number) }),
                uploadId: uploadID
            )).eTag
        }
    }

    public func abortMultipartUpload(bucket: String, key: String, uploadID: String) async throws {
        _ = try await s3.abortMultipartUpload(.init(bucket: bucket, key: key, uploadId: uploadID))
    }

    private func mapped<T>(key: String, _ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch where S3Service.isPreconditionFailure(error) {
            throw BucketeerError.preconditionFailed(key: key)
        }
    }
}
