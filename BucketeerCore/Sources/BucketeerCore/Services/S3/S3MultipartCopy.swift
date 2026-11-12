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
    /// The tags of `source` (of `source.versionId`, if set).
    func tags(of source: S3MultipartCopy.Source) async throws -> [String: String]
    /// Starts the multipart upload; returns its upload ID.
    func createMultipartCopy(_ request: S3.CreateMultipartUploadRequest) async throws -> String
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
/// written (`largeCopyUnsupported`). The properties come from the HEAD
/// that established the ETag; the tags are read separately and, without
/// a version ID, can belong to a different write (documented limit).
public enum S3MultipartCopy {

    public struct Source: Sendable, Equatable {
        public let bucket: String
        public let key: String
        public let etag: String
        public let size: Int64
        /// The version every range is read from. `"null"` (the version of
        /// an object written while versioning was off) selects that
        /// version but does not pin it: it is overwritten in place, so
        /// its ranges are additionally bound by the ETag.
        public var versionId: String?
        /// The properties a copy keeps, as of the HEAD that read `etag`.
        public var properties: Properties
        /// Replaces the source's user metadata on the copy.
        public var metadata: [String: String]?
        /// Replaces all of the source's properties (metadata edit).
        public var replacement: ObjectMetadata?

        public init(bucket: String, key: String, etag: String, size: Int64, versionId: String? = nil,
                    properties: Properties = Properties(), metadata: [String: String]? = nil,
                    replacement: ObjectMetadata? = nil) {
            self.bucket = bucket
            self.key = key
            self.etag = etag
            self.size = size
            self.versionId = versionId
            self.properties = properties
            self.metadata = metadata
            self.replacement = replacement
        }

        /// The source as `head` describes it. A requested version stays
        /// the selector, `"null"` included; without one, the version the
        /// HEAD reports pins the copy unless it is the mutable `"null"`.
        public init(bucket: String, key: String, head: S3.HeadObjectOutput, requestedVersion: String? = nil) {
            let reported = head.versionId == nullVersion ? nil : head.versionId
            self.init(bucket: bucket, key: key, etag: ETag.normalized(head.eTag ?? ""),
                      size: head.contentLength ?? 0, versionId: requestedVersion ?? reported,
                      properties: Properties(head: head))
        }

        /// True when `versionId` names one immutable version.
        var pinsVersion: Bool {
            versionId.map { $0 != nullVersion } ?? false
        }
    }

    /// The properties CopyObject keeps besides the bytes.
    public struct Properties: Sendable, Equatable {
        public var cacheControl: String?
        public var contentDisposition: String?
        public var contentEncoding: String?
        public var contentLanguage: String?
        public var contentType: String?
        public var expires: String?
        public var metadata: [String: String]?
        public var storageClass: S3.StorageClass?
        public var websiteRedirectLocation: String?

        public init() {}

        public init(head: S3.HeadObjectOutput) {
            cacheControl = head.cacheControl
            contentDisposition = head.contentDisposition
            contentEncoding = head.contentEncoding
            contentLanguage = head.contentLanguage
            contentType = head.contentType
            expires = head.expires
            metadata = head.metadata
            storageClass = head.storageClass
            websiteRedirectLocation = head.websiteRedirectLocation
        }
    }

    /// The version ID S3 reports for an object written without versioning.
    static let nullVersion = "null"

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
            if source.pinsVersion { return .version }
            if enforced.contains(.partCopySourceIfMatch) { return .sourceCondition }
        }
        if enforced.contains(.readIfMatch) { return .relay }
        throw BucketeerError.largeCopyUnsupported(key: source.key)
    }

    /// Copies `source` to `toKey`, completing only while `precondition`
    /// holds for the destination: as a completion header where the
    /// provider enforces it, else checked with a HEAD right before.
    /// Returns the ETag of the copy. `partSize` defaults to
    /// `defaultPartSize` for server-side ranges and to the upload part
    /// size for relayed ones (they pass through memory).
    public static func copy(
        _ source: Source,
        toBucket: String,
        toKey: String,
        precondition: WritePrecondition?,
        provider: S3Provider,
        copier: any S3ObjectCopying,
        partSize: Int? = nil
    ) async throws -> String? {
        let pin = try pin(for: source, provider: provider)
        let preferred = partSize ?? (pin == .relay ? S3FileUpload.defaultPartSize : defaultPartSize)
        let partSize = S3FileUpload.partSize(forFileOf: source.size, preferred: preferred)
        let tags = try await tags(of: source, provider: provider, copier: copier)
        let uploadID = try await copier.createMultipartCopy(
            createRequest(for: source, tags: tags, toBucket: toBucket, toKey: toKey)
        )
        do {
            var parts: [S3CompletedPart] = []
            for (index, range) in ranges(size: source.size, partSize: partSize).enumerated() {
                try Task.checkCancellation()
                let etag = try await copyPart(range, number: index + 1, of: source, pin: pin,
                                              toBucket: toBucket, toKey: toKey, uploadID: uploadID, copier: copier)
                parts.append(S3CompletedPart(number: index + 1, etag: etag))
            }
            let enforced = provider.conditionalRequests
            let headers = enforced.contains(.completionConditions)
                ? S3Service.headers(for: precondition, enforced: enforced)
                : S3Service.headers(for: nil, enforced: [])
            if let precondition, headers.ifMatch == nil, headers.ifNoneMatch == nil {
                let current = try await copier.currentETag(bucket: toBucket, key: toKey)
                try PreconditionCheck.verify(precondition, current: current, key: toKey)
            }
            let etag = try await copier.completeMultipartUpload(
                bucket: toBucket, key: toKey, uploadID: uploadID, parts: parts,
                ifMatch: headers.ifMatch, ifNoneMatch: headers.ifNoneMatch
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
            let body = try await copier.read(bucket: source.bucket, key: source.key, versionId: source.versionId,
                                             range: range, ifMatch: ETag.quoted(source.etag))
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

    /// The tags the copy gets: the edited ones, else the source's;
    /// `nil` where the provider has no tagging.
    private static func tags(of source: Source, provider: S3Provider,
                             copier: any S3ObjectCopying) async throws -> [String: String]? {
        guard provider.supportsObjectTagging else { return nil }
        if let replacement = source.replacement { return replacement.tags }
        return try await copier.tags(of: source)
    }

    /// The CreateMultipartUpload request for a copy: the properties a
    /// CopyObject would keep (headers, user metadata, storage class,
    /// tags), or `source.replacement` for a metadata edit. `tags` is
    /// `nil` where the provider has no tagging.
    static func createRequest(for source: Source, tags: [String: String]?,
                              toBucket: String, toKey: String) -> S3.CreateMultipartUploadRequest {
        let tagging = tags.flatMap(taggingHeader)
        guard let replacement = source.replacement else {
            let kept = source.properties
            return .init(
                bucket: toBucket, cacheControl: kept.cacheControl, contentDisposition: kept.contentDisposition,
                contentEncoding: kept.contentEncoding, contentLanguage: kept.contentLanguage,
                contentType: kept.contentType, expires: kept.expires, key: toKey,
                metadata: source.metadata.map { BucketeerEnvelope.preservingMarker(in: $0, from: kept.metadata) } ?? kept.metadata, storageClass: kept.storageClass, tagging: tagging,
                websiteRedirectLocation: kept.websiteRedirectLocation
            )
        }
        return .init(
            bucket: toBucket, cacheControl: replacement.cacheControl.nonEmpty,
            contentDisposition: replacement.contentDisposition.nonEmpty,
            contentEncoding: replacement.contentEncoding.nonEmpty, contentType: replacement.contentType.nonEmpty,
            key: toKey, metadata: BucketeerEnvelope.preservingMarker(in: replacement.userMetadata, from: source.properties.metadata),
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

    public func createMultipartCopy(_ request: S3.CreateMultipartUploadRequest) async throws -> String {
        guard let uploadID = try await s3.createMultipartUpload(request).uploadId else {
            throw BucketeerError.providerError(statusCode: 0, message: "The provider returned no multipart upload ID.")
        }
        return uploadID
    }

    public func tags(of source: S3MultipartCopy.Source) async throws -> [String: String] {
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

    public func read(bucket: String, key: String, versionId: String?, range: ClosedRange<Int64>,
                     ifMatch: String) async throws -> Data {
        try await SotoRangeReader(s3: s3).read(bucket: bucket, key: key, versionId: versionId, range: range,
                                               ifMatch: ifMatch)
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
