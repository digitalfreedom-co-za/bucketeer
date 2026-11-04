//
//  S3PinnedDownload.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
@preconcurrency import SotoS3

/// Reads one byte range of an object (of `versionId`, if set), only
/// while it has the ETag given in `ifMatch`; a replaced object throws
/// `.preconditionFailed`.
public protocol S3RangeReading: Sendable {
    func read(bucket: String, key: String, versionId: String?, range: ClosedRange<Int64>,
              ifMatch: String) async throws -> Data
}

/// Downloads a large object range by range, every range pinned to the
/// same version with `If-Match`. Soto's `multipartDownload` pins only
/// its initial HEAD, so an object replaced mid-download would yield a
/// file stitched together from two versions.
public enum S3PinnedDownload {

    public static func download(
        bucket: String,
        key: String,
        etag: String,
        size: Int64,
        partSize: Int,
        to url: URL,
        reader: any S3RangeReading
    ) async throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw BucketeerError.sandboxAccessDenied(url)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var offset: Int64 = 0
        while offset < size {
            try Task.checkCancellation()
            let last = min(offset + Int64(partSize), size) - 1
            let data = try await reader.read(bucket: bucket, key: key, versionId: nil, range: offset...last,
                                             ifMatch: ETag.quoted(etag))
            guard data.count == Int(last - offset + 1) else {
                throw BucketeerError.preconditionFailed(key: key)
            }
            try handle.write(contentsOf: data)
            offset = last + 1
        }
    }
}

/// `S3RangeReading` on a Soto `S3` client.
public struct SotoRangeReader: S3RangeReading {
    private let s3: S3

    public init(s3: S3) {
        self.s3 = s3
    }

    public func read(bucket: String, key: String, versionId: String?, range: ClosedRange<Int64>,
                     ifMatch: String) async throws -> Data {
        do {
            let response = try await s3.getObject(.init(
                bucket: bucket, ifMatch: ifMatch, key: key,
                range: "bytes=\(range.lowerBound)-\(range.upperBound)", versionId: versionId
            ))
            let buffer = try await response.body.collect(upTo: range.count)
            return Data(buffer.readableBytesView)
        } catch where S3Service.isPreconditionFailure(error) {
            throw BucketeerError.preconditionFailed(key: key)
        }
    }
}
