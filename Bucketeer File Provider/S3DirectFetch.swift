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

    static func download(
        account: S3Account,
        bucket: String,
        key: String,
        size: Int64,
        to localURL: URL,
        factory: S3ClientFactory
    ) async throws {
        let s3 = try await factory.client(for: account)
        try? FileManager.default.removeItem(at: localURL)
        if size == 0 {
            FileManager.default.createFile(atPath: localURL.path, contents: nil)
            return
        }
        if size < multipartThreshold {
            let response = try await s3.getObject(.init(bucket: bucket, key: key))
            let buffer = try await response.body.collect(upTo: Int(size) + 1)
            let data = Data(buffer.readableBytesView)
            try data.write(to: localURL)
            return
        }
        _ = try await s3.multipartDownload(
            .init(bucket: bucket, key: key),
            partSize: multipartPartSize,
            filename: localURL.path,
            progress: { @Sendable _ in }
        )
    }

    static func upload(
        account: S3Account,
        bucket: String,
        key: String,
        localURL: URL,
        contentType: String?,
        factory: S3ClientFactory
    ) async throws {
        let s3 = try await factory.client(for: account)
        let size = (try? localURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let fileSize = Int64(size)
        if fileSize >= multipartThreshold {
            _ = try await s3.multipartUpload(
                .init(
                    bucket: bucket,
                    contentType: contentType,
                    key: key
                ),
                partSize: multipartPartSize,
                filename: localURL.path,
                progress: { @Sendable _ in }
            )
        } else {
            let data = try Data(contentsOf: localURL, options: .mappedIfSafe)
            let buffer = ByteBuffer(bytes: data)
            _ = try await s3.putObject(.init(
                body: AWSHTTPBody(buffer: buffer),
                bucket: bucket,
                contentType: contentType,
                key: key
            ))
        }
    }
}
