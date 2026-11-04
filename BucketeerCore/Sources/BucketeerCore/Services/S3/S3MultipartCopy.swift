//
//  S3MultipartCopy.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
@preconcurrency import SotoS3

/// The S3 requests a ranged server-side copy needs; `SotoObjectWriter`
/// is the production implementation.
public protocol S3ObjectCopying: Sendable {
    /// The object's ETag, or `nil` when there is none.
    func currentETag(bucket: String, key: String) async throws -> String?
    /// Starts a multipart upload that carries the source's content type
    /// and metadata (or `source.metadata` instead of its user metadata).
    func createMultipartCopy(of source: S3MultipartCopy.Source, toBucket: String, toKey: String) async throws -> String
    func uploadPartCopy(of source: S3MultipartCopy.Source, range: ClosedRange<Int64>, toBucket: String, toKey: String,
                        uploadID: String, partNumber: Int) async throws -> String
    func completeMultipartUpload(bucket: String, key: String, uploadID: String, parts: [S3CompletedPart],
                                 ifMatch: String?, ifNoneMatch: String?) async throws -> String?
    func abortMultipartUpload(bucket: String, key: String, uploadID: String) async throws
}

/// Server-side copy of an object too large for one CopyObject (AWS:
/// 5 GB), range by range with UploadPartCopy. Ranges are not pinned
/// to the version (R2 refuses copy-source conditions on parts), so the
/// source ETag is compared again right before the completion: a source
/// replaced during the copy aborts it instead of producing a mix.
public enum S3MultipartCopy {

    public struct Source: Sendable, Equatable {
        public let bucket: String
        public let key: String
        public let etag: String
        public let size: Int64
        /// Replaces the source's user metadata on the copy.
        public var metadata: [String: String]?

        public init(bucket: String, key: String, etag: String, size: Int64, metadata: [String: String]? = nil) {
            self.bucket = bucket
            self.key = key
            self.etag = etag
            self.size = size
            self.metadata = metadata
        }
    }

    public static let defaultPartSize = 256 * 1024 * 1024

    /// True when one CopyObject cannot take `size` bytes. AWS documents
    /// 5 GB, Storj about 671 GB; the others document no limit, so they
    /// get the AWS one.
    public static func needsParts(size: Int64, provider: S3Provider) -> Bool {
        size > (provider == .storj ? 671_000_000_000 : 5_000_000_000)
    }

    /// Copies `source` to `toKey`; with `ifAbsent` only while nothing is
    /// there. Returns the ETag of the copy.
    public static func copy(
        _ source: Source,
        toBucket: String,
        toKey: String,
        ifAbsent: Bool,
        enforced: S3Provider.ConditionalRequests,
        copier: any S3ObjectCopying,
        partSize: Int = defaultPartSize
    ) async throws -> String? {
        let partSize = S3FileUpload.partSize(forFileOf: source.size, preferred: partSize)
        let uploadID = try await copier.createMultipartCopy(of: source, toBucket: toBucket, toKey: toKey)
        do {
            var parts: [S3CompletedPart] = []
            for (index, range) in ranges(size: source.size, partSize: partSize).enumerated() {
                try Task.checkCancellation()
                let etag = try await copier.uploadPartCopy(of: source, range: range, toBucket: toBucket, toKey: toKey,
                                                           uploadID: uploadID, partNumber: index + 1)
                parts.append(S3CompletedPart(number: index + 1, etag: etag))
            }
            let current = try await copier.currentETag(bucket: source.bucket, key: source.key)
            try PreconditionCheck.verify(.ifMatch(source.etag), current: current, key: toKey)
            let sendsIfAbsent = ifAbsent && enforced.isSuperset(of: [.writeIfAbsent, .completionConditions])
            if ifAbsent, !sendsIfAbsent {
                let existing = try await copier.currentETag(bucket: toBucket, key: toKey)
                try PreconditionCheck.verify(.ifAbsent, current: existing, key: toKey)
            }
            let etag = try await copier.completeMultipartUpload(
                bucket: toBucket, key: toKey, uploadID: uploadID, parts: parts,
                ifMatch: nil, ifNoneMatch: sendsIfAbsent ? "*" : nil
            )
            return etag.map(ETag.normalized)
        } catch {
            try? await copier.abortMultipartUpload(bucket: toBucket, key: toKey, uploadID: uploadID)
            throw error
        }
    }

    static func ranges(size: Int64, partSize: Int) -> [ClosedRange<Int64>] {
        stride(from: Int64(0), to: size, by: partSize).map { start in
            start...(min(start + Int64(partSize), size) - 1)
        }
    }
}

extension SotoObjectWriter: S3ObjectCopying {

    public func createMultipartCopy(of source: S3MultipartCopy.Source, toBucket: String, toKey: String) async throws -> String {
        let head = try await s3.headObject(.init(bucket: source.bucket, key: source.key))
        let output = try await s3.createMultipartUpload(.init(
            bucket: toBucket,
            cacheControl: head.cacheControl,
            contentDisposition: head.contentDisposition,
            contentEncoding: head.contentEncoding,
            contentType: head.contentType,
            key: toKey,
            metadata: source.metadata ?? head.metadata,
            storageClass: head.storageClass
        ))
        guard let uploadID = output.uploadId else {
            throw BucketeerError.providerError(statusCode: 0, message: "The provider returned no multipart upload ID.")
        }
        return uploadID
    }

    public func uploadPartCopy(of source: S3MultipartCopy.Source, range: ClosedRange<Int64>, toBucket: String,
                               toKey: String, uploadID: String, partNumber: Int) async throws -> String {
        let path = "\(source.bucket)/\(source.key)"
        let output = try await s3.uploadPartCopy(.init(
            bucket: toBucket,
            copySource: path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path,
            copySourceRange: "bytes=\(range.lowerBound)-\(range.upperBound)",
            key: toKey,
            partNumber: partNumber,
            uploadId: uploadID
        ))
        guard let etag = output.copyPartResult.eTag else {
            throw BucketeerError.providerError(statusCode: 0, message: "The provider returned no ETag for part \(partNumber).")
        }
        return etag
    }
}
