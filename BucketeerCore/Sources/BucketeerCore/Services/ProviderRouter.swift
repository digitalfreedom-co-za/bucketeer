//
//  ProviderRouter.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation

/// `S3Browsing` facade that fans out to the per-family backend (Soto for
/// the S3 family, `AzureBlobObjectStore` for Azure). View models and the
/// transfer manager talk to this router instead of either concrete
/// implementation so adding a third backend (e.g. GCS native, Backblaze
/// B2 native) in the future is local to this file.
public struct ProviderRouter: S3Browsing {
    public let s3: any S3Browsing
    public let azure: any S3Browsing

    public init(s3: any S3Browsing, azure: any S3Browsing) {
        self.s3 = s3
        self.azure = azure
    }

    private func backend(for account: S3Account) -> any S3Browsing {
        switch account.provider.family {
        case .s3:        return s3
        case .azureBlob: return azure
        }
    }

    // MARK: - S3Browsing

    public func listBuckets(account: S3Account) async throws -> [S3Bucket] {
        try await backend(for: account).listBuckets(account: account)
    }

    public func listObjects(
        account: S3Account,
        bucket: String,
        prefix: String,
        continuationToken: String?
    ) async throws -> S3Page {
        try await backend(for: account).listObjects(
            account: account,
            bucket: bucket,
            prefix: prefix,
            continuationToken: continuationToken
        )
    }

    public func head(account: S3Account, bucket: String, key: String) async throws -> S3Object {
        try await backend(for: account).head(
            account: account,
            bucket: bucket,
            key: key
        )
    }

    public func delete(account: S3Account, bucket: String, keys: [String]) async throws {
        try await backend(for: account).delete(
            account: account,
            bucket: bucket,
            keys: keys
        )
    }

    public func copy(
        account: S3Account,
        fromBucket: String,
        fromKey: String,
        toBucket: String,
        toKey: String,
        metadata: [String: String]?
    ) async throws {
        try await backend(for: account).copy(
            account: account,
            fromBucket: fromBucket,
            fromKey: fromKey,
            toBucket: toBucket,
            toKey: toKey,
            metadata: metadata
        )
    }

    public func createFolder(account: S3Account, bucket: String, prefix: String) async throws {
        try await backend(for: account).createFolder(
            account: account,
            bucket: bucket,
            prefix: prefix
        )
    }

    public func presignedDownloadURL(
        account: S3Account,
        bucket: String,
        key: String,
        ttl: TimeInterval
    ) async throws -> URL {
        try await backend(for: account).presignedDownloadURL(
            account: account,
            bucket: bucket,
            key: key,
            ttl: ttl
        )
    }
}
