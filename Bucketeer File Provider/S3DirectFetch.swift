//
//  S3DirectFetch.swift
//  Bucketeer File Provider
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
@preconcurrency import SotoS3
@preconcurrency import NIOCore
import BucketeerCore

/// Direct upload / download primitives for the File Provider. Bypasses
/// the host's `TransferManager` queue — the extension has no UI to feed
/// progress into, and the system manages its own progress reporting.
enum S3DirectFetch {

    private static let multipartThreshold: Int64 = 5 * 1024 * 1024
    private static let multipartPartSize: Int = 8 * 1024 * 1024

    /// Every GET carries `If-Match: etag`, so the bytes are exactly the
    /// version the caller reports; a replaced object surfaces as
    /// `BucketeerError.preconditionFailed`.
    static func download(
        account: S3Account,
        bucket: String,
        key: String,
        etag: String,
        size: Int64,
        to localURL: URL,
        factory: S3ClientFactory
    ) async throws {
        let s3 = try await factory.client(for: account)
        let request = S3.GetObjectRequest(bucket: bucket, ifMatch: ETag.quoted(etag), key: key)
        do {
            try await StagedDownload.write(to: localURL) { staging in
                if size == 0 {
                    try Data().write(to: staging)
                } else if size < multipartThreshold {
                    let response = try await s3.getObject(request)
                    let buffer = try await response.body.collect(upTo: Int(size) + 1)
                    try Data(buffer.readableBytesView).write(to: staging)
                } else {
                    try await S3PinnedDownload.download(
                        bucket: bucket, key: key, etag: etag, size: size,
                        partSize: multipartPartSize, to: staging, reader: SotoRangeReader(s3: s3)
                    )
                }
            }
        } catch where S3Service.isPreconditionFailure(error) {
            throw BucketeerError.preconditionFailed(key: key)
        }
    }

    /// With a `precondition` the write only succeeds while it holds; a
    /// refusal surfaces as `BucketeerError.preconditionFailed`.
    /// Conditional writes stream large files as a multipart upload with
    /// the precondition on the completion (`S3ConditionalUpload`), so
    /// the extension never holds a whole file in memory.
    /// Returns the ETag the write answered with (unquoted).
    @discardableResult
    static func upload(
        account: S3Account,
        bucket: String,
        key: String,
        localURL: URL,
        contentType: String?,
        precondition: WritePrecondition? = nil,
        factory: S3ClientFactory
    ) async throws -> String? {
        let s3 = try await factory.client(for: account)
        let size = (try? localURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let fileSize = Int64(size)
        if let precondition {
            return try await S3ConditionalUpload.upload(
                fileAt: localURL,
                bucket: bucket,
                key: key,
                contentType: contentType,
                precondition: precondition,
                writer: SotoObjectWriter(s3: s3)
            )
        } else if fileSize >= multipartThreshold {
            let output = try await s3.multipartUpload(
                .init(
                    bucket: bucket,
                    contentType: contentType,
                    key: key
                ),
                partSize: multipartPartSize,
                filename: localURL.path,
                progress: { @Sendable _ in }
            )
            return output.eTag.map(ETag.normalized)
        } else {
            let data = try Data(contentsOf: localURL, options: .mappedIfSafe)
            let buffer = ByteBuffer(bytes: data)
            let output = try await s3.putObject(.init(
                body: AWSHTTPBody(buffer: buffer),
                bucket: bucket,
                contentType: contentType,
                key: key
            ))
            return output.eTag.map(ETag.normalized)
        }
    }
}
