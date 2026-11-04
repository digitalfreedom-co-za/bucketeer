//
//  S3MultipartCopy.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
@preconcurrency import SotoS3

/// The S3 requests a ranged copy needs; `SotoObjectWriter` is the
/// production implementation. Ranges come either from UploadPartCopy
/// or, relayed, from a ranged GET followed by UploadPart.
public protocol S3ObjectCopying: S3RangeReading {
    /// The object's ETag, or `nil` when there is none.
    func currentETag(bucket: String, key: String) async throws -> String?
    /// Starts a multipart upload that carries the source's properties
    /// (`S3MultipartCopy.createRequest`); its tags only with `copiesTags`.
    func createMultipartCopy(of source: S3MultipartCopy.Source, toBucket: String, toKey: String,
                             copiesTags: Bool) async throws -> String
    /// Copies `range` of `source` (of `source.versionId`, if set) as
    /// one part, with `sourceIfMatch` as the copy-source condition.
    func uploadPartCopy(of source: S3MultipartCopy.Source, range: ClosedRange<Int64>, toBucket: String, toKey: String,
                        uploadID: String, partNumber: Int, sourceIfMatch: String?) async throws -> String
    func uploadPart(bucket: String, key: String, uploadID: String, partNumber: Int, body: Data) async throws -> String
    func completeMultipartUpload(bucket: String, key: String, uploadID: String, parts: [S3CompletedPart],
                                 ifMatch: String?, ifNoneMatch: String?) async throws -> String?
    func abortMultipartUpload(bucket: String, key: String, uploadID: String) async throws
}

/// Copy of an object too large for one CopyObject (AWS: 5 GB), range by
/// range. Every range is pinned to the source version that was read, so
/// a source replaced during the copy — even replaced and put back — can
/// never end up mixed into it:
/// - a known version ID pins UploadPartCopy to that version;
/// - otherwise each UploadPartCopy carries `x-amz-copy-source-if-match`
///   where the provider enforces it;
/// - otherwise the bytes are relayed through ranged GETs with `If-Match`.
/// A provider with none of these refuses the copy before anything is
/// written (`largeCopyUnsupported`).
public enum S3MultipartCopy {

    public struct Source: Sendable, Equatable {
        public let bucket: String
        public let key: String
        public let etag: String
        public let size: Int64
        /// The source version; pins every range when set. `"null"` (the
        /// version of an object written while versioning was off) is no
        /// pin, it is overwritten in place, so it is dropped.
        public var versionId: String? {
            didSet { if versionId == "null" { versionId = nil } }
        }
        /// Replaces the source's user metadata on the copy.
        public var metadata: [String: String]?
        /// Replaces all of the source's properties (metadata edit).
        public var replacement: ObjectMetadata?

        public init(bucket: String, key: String, etag: String, size: Int64, versionId: String? = nil,
                    metadata: [String: String]? = nil, replacement: ObjectMetadata? = nil) {
            self.bucket = bucket
            self.key = key
            self.etag = etag
            self.size = size
            self.versionId = versionId == "null" ? nil : versionId
            self.metadata = metadata
            self.replacement = replacement
        }
    }

    /// How the ranges are bound to the source version.
    enum Pin: Equatable {
        case version
        case sourceCondition
        case relay
    }

    public static let defaultPartSize = 256 * 1024 * 1024

    /// True when one CopyObject cannot take `size` bytes. AWS documents
    /// 5 GB, Storj about 671 GB; the others document no limit, so they
    /// get the AWS one.
    public static func needsParts(size: Int64, provider: S3Provider) -> Bool {
        size > (provider == .storj ? 671_000_000_000 : 5_000_000_000)
    }

    static func pin(for source: Source, provider: S3Provider) throws -> Pin {
        let enforced = provider.conditionalRequests
        if provider.supportsUploadPartCopy {
            if source.versionId != nil { return .version }
            if enforced.contains(.partCopySourceIfMatch) { return .sourceCondition }
        }
        if enforced.contains(.readIfMatch) { return .relay }
        throw BucketeerError.largeCopyUnsupported(key: source.key)
    }

    /// Copies `source` to `toKey`; with `ifAbsent` only while nothing is
    /// there. Returns the ETag of the copy. `partSize` defaults to
    /// `defaultPartSize` for server-side ranges and to the upload part
    /// size for relayed ones (they pass through memory).
    public static func copy(
        _ source: Source,
        toBucket: String,
        toKey: String,
        ifAbsent: Bool,
        provider: S3Provider,
        copier: any S3ObjectCopying,
        partSize: Int? = nil
    ) async throws -> String? {
        let pin = try pin(for: source, provider: provider)
        let preferred = partSize ?? (pin == .relay ? S3FileUpload.defaultPartSize : defaultPartSize)
        let partSize = S3FileUpload.partSize(forFileOf: source.size, preferred: preferred)
        let uploadID = try await copier.createMultipartCopy(of: source, toBucket: toBucket, toKey: toKey,
                                                            copiesTags: provider.supportsObjectTagging)
        do {
            var parts: [S3CompletedPart] = []
            for (index, range) in ranges(size: source.size, partSize: partSize).enumerated() {
                try Task.checkCancellation()
                let etag = try await copyPart(range, number: index + 1, of: source, pin: pin,
                                              toBucket: toBucket, toKey: toKey, uploadID: uploadID, copier: copier)
                parts.append(S3CompletedPart(number: index + 1, etag: etag))
            }
            let enforced = provider.conditionalRequests
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
            if S3Service.isPreconditionFailure(error) {
                throw BucketeerError.preconditionFailed(key: toKey)
            }
            throw error
        }
    }

    private static func copyPart(
        _ range: ClosedRange<Int64>, number: Int, of source: Source, pin: Pin,
        toBucket: String, toKey: String, uploadID: String, copier: any S3ObjectCopying
    ) async throws -> String {
        switch pin {
        case .version, .sourceCondition:
            return try await copier.uploadPartCopy(
                of: source, range: range, toBucket: toBucket, toKey: toKey, uploadID: uploadID, partNumber: number,
                sourceIfMatch: pin == .sourceCondition ? ETag.quoted(source.etag) : nil
            )
        case .relay:
            let body = try await copier.read(bucket: source.bucket, key: source.key, range: range,
                                             ifMatch: ETag.quoted(source.etag))
            guard body.count == range.count else { throw BucketeerError.preconditionFailed(key: toKey) }
            return try await copier.uploadPart(bucket: toBucket, key: toKey, uploadID: uploadID,
                                               partNumber: number, body: body)
        }
    }

    static func ranges(size: Int64, partSize: Int) -> [ClosedRange<Int64>] {
        stride(from: Int64(0), to: size, by: partSize).map { start in
            start...(min(start + Int64(partSize), size) - 1)
        }
    }

    /// The CreateMultipartUpload request for a copy: the properties a
    /// CopyObject would keep (headers, user metadata, storage class,
    /// tags), or `source.replacement` for a metadata edit. `tags` is
    /// `nil` where the provider has no tagging.
    static func createRequest(for source: Source, head: S3.HeadObjectOutput, tags: [String: String]?,
                              toBucket: String, toKey: String) -> S3.CreateMultipartUploadRequest {
        let tagging = tags.flatMap(taggingHeader)
        guard let replacement = source.replacement else {
            return .init(
                bucket: toBucket, cacheControl: head.cacheControl, contentDisposition: head.contentDisposition,
                contentEncoding: head.contentEncoding, contentLanguage: head.contentLanguage,
                contentType: head.contentType, expires: head.expires, key: toKey,
                metadata: source.metadata ?? head.metadata, storageClass: head.storageClass, tagging: tagging,
                websiteRedirectLocation: head.websiteRedirectLocation
            )
        }
        return .init(
            bucket: toBucket, cacheControl: replacement.cacheControl.nonEmpty,
            contentDisposition: replacement.contentDisposition.nonEmpty,
            contentEncoding: replacement.contentEncoding.nonEmpty, contentType: replacement.contentType.nonEmpty,
            key: toKey, metadata: replacement.userMetadata.isEmpty ? nil : replacement.userMetadata,
            storageClass: replacement.storageClass.flatMap(S3.StorageClass.init(rawValue:)), tagging: tagging
        )
    }

    /// `x-amz-tagging`: URL query form, keys and values percent-encoded.
    private static func taggingHeader(_ tags: [String: String]) -> String? {
        guard !tags.isEmpty else { return nil }
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        func encoded(_ text: String) -> String {
            text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
        }
        return tags.sorted { $0.key < $1.key }
            .map { "\(encoded($0.key))=\(encoded($0.value))" }
            .joined(separator: "&")
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

extension SotoObjectWriter: S3ObjectCopying {

    public func createMultipartCopy(of source: S3MultipartCopy.Source, toBucket: String, toKey: String,
                                    copiesTags: Bool) async throws -> String {
        let head = try await s3.headObject(.init(bucket: source.bucket, key: source.key, versionId: source.versionId))
        var tags: [String: String]?
        if copiesTags {
            if let replacement = source.replacement {
                tags = replacement.tags
            } else {
                tags = try await sourceTags(of: source)
            }
        }
        let request = S3MultipartCopy.createRequest(for: source, head: head, tags: tags, toBucket: toBucket, toKey: toKey)
        guard let uploadID = try await s3.createMultipartUpload(request).uploadId else {
            throw BucketeerError.providerError(statusCode: 0, message: "The provider returned no multipart upload ID.")
        }
        return uploadID
    }

    private func sourceTags(of source: S3MultipartCopy.Source) async throws -> [String: String] {
        let tagging = try await s3.getObjectTagging(.init(bucket: source.bucket, key: source.key,
                                                          versionId: source.versionId))
        return Dictionary(tagging.tagSet.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
    }

    public func uploadPartCopy(of source: S3MultipartCopy.Source, range: ClosedRange<Int64>, toBucket: String,
                               toKey: String, uploadID: String, partNumber: Int,
                               sourceIfMatch: String?) async throws -> String {
        let output = try await s3.uploadPartCopy(.init(
            bucket: toBucket,
            copySource: S3MultipartCopy.copySourceHeader(bucket: source.bucket, key: source.key,
                                                         versionId: source.versionId),
            copySourceIfMatch: sourceIfMatch,
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

    public func read(bucket: String, key: String, range: ClosedRange<Int64>, ifMatch: String) async throws -> Data {
        try await SotoRangeReader(s3: s3).read(bucket: bucket, key: key, range: range, ifMatch: ifMatch)
    }
}

extension S3MultipartCopy {

    /// `x-amz-copy-source`: bucket and key path-encoded, the version ID
    /// as a strictly encoded query value — the `?versionId=` separator
    /// itself must stay literal.
    public static func copySourceHeader(bucket: String, key: String, versionId: String?) -> String {
        let path = "\(bucket)/\(key)"
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let versionId else { return encodedPath }
        var queryValueAllowed = CharacterSet.alphanumerics
        queryValueAllowed.insert(charactersIn: "-._~")
        let encodedVersion = versionId.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? versionId
        return "\(encodedPath)?versionId=\(encodedVersion)"
    }
}
