//
//  PreviewDownloader.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
@preconcurrency import SotoS3
@preconcurrency import NIOCore

/// Background download bridge for `PreviewCache`. Owns the per-family
/// dispatch logic that the cache itself is too generic to know about.
/// Keeps the cache provider-agnostic.
///
/// **Not user-visible** — downloads here do not appear in the
/// `TransferManager` queue, by design: previews are an implementation
/// detail of the detail pane and should not clutter the user's recent
/// transfers list.
struct PreviewDownloader: Sendable {
    let s3Factory: S3ClientFactory
    let azureTransporter: AzureBlobTransporter

    func fetch(
        account: S3Account,
        bucket: String,
        key: String,
        to localURL: URL
    ) async throws {
        switch account.provider.family {
        case .s3:
            try await fetchFromS3(
                account: account,
                bucket: bucket,
                key: key,
                to: localURL
            )
        case .azureBlob:
            try await azureTransporter.download(
                account: account,
                container: bucket,
                blob: key,
                localURL: localURL,
                progress: { _, _ in /* silent */ }
            )
        }
    }

    private func fetchFromS3(
        account: S3Account,
        bucket: String,
        key: String,
        to localURL: URL
    ) async throws {
        let s3 = try await s3Factory.client(for: account)

        // Pre-flight HEAD to learn size — small objects use single-shot
        // GET, large objects use the multipart download path so the
        // local file lands correctly.
        let head: S3.HeadObjectOutput
        do {
            head = try await s3.headObject(.init(bucket: bucket, key: key))
        } catch {
            throw Self.translate(error, bucket: bucket, key: key)
        }
        let size = head.contentLength ?? 0

        try? FileManager.default.removeItem(at: localURL)

        // Mirror the threshold used by the user-visible transfer
        // manager so preview previews and downloads behave consistently.
        let multipartThreshold: Int64 = 5 * 1024 * 1024
        let partSize: Int = 8 * 1024 * 1024

        do {
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
                partSize: partSize,
                filename: localURL.path,
                progress: { @Sendable _ in }
            )
        } catch {
            try? FileManager.default.removeItem(at: localURL)
            throw Self.translate(error, bucket: bucket, key: key)
        }
    }

    private static func translate(_ error: Error, bucket: String, key: String) -> Error {
        if let existing = error as? BucketeerError { return existing }
        // PreviewDownloader runs out of band — surface a generic error
        // and let the calling view decide whether to show it or fall
        // back to the explicit-click flow.
        return BucketeerError.unknown(message: error.localizedDescription)
    }
}
