//
//  ServiceProtocols.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation

// MARK: - KeychainStoring

/// Persists S3 credentials in the macOS Keychain access group shared
/// with the File Provider extension. The store knows nothing about
/// accounts beyond their `id`.
public protocol KeychainStoring: Sendable {
    func save(_ credentials: AccountCredentials, for accountID: UUID) async throws
    func load(for accountID: UUID) async throws -> AccountCredentials
    func delete(for accountID: UUID) async throws
}

// MARK: - AccountStoring

/// Persists non-secret account metadata. Backed by SwiftData inside the
/// App Group container.
public protocol AccountStoring: Sendable {
    func all() async throws -> [S3Account]
    func upsert(_ account: S3Account) async throws
    func delete(id: UUID) async throws
    func touchLastUsed(id: UUID) async throws
}

// MARK: - S3Browsing

/// One-shot S3 operations. Implementations build a `SotoS3.S3` per call
/// via `S3ClientFactory`, reusing the cached `AWSClient` for the account.
public protocol S3Browsing: Sendable {
    func listBuckets(account: S3Account) async throws -> [S3Bucket]
    func listObjects(
        account: S3Account,
        bucket: String,
        prefix: String,
        continuationToken: String?
    ) async throws -> S3Page
    func head(account: S3Account, bucket: String, key: String) async throws -> S3Object
    func delete(account: S3Account, bucket: String, keys: [String]) async throws
    func copy(
        account: S3Account,
        fromBucket: String,
        fromKey: String,
        toBucket: String,
        toKey: String,
        metadata: [String: String]?
    ) async throws
    func createFolder(account: S3Account, bucket: String, prefix: String) async throws
}

// MARK: - Transferring

/// Long-running upload / download queue. Reports progress through an
/// `AsyncStream` so view models stay decoupled from the underlying task
/// graph.
public protocol Transferring: Sendable {
    @discardableResult
    func enqueueUpload(
        account: S3Account,
        bucket: String,
        key: String,
        localURL: URL,
        contentType: String?
    ) async -> UUID

    @discardableResult
    func enqueueDownload(
        account: S3Account,
        bucket: String,
        key: String,
        localURL: URL
    ) async -> UUID

    func cancel(id: UUID) async

    /// Live snapshot stream of the current task list. Each yielded value
    /// is the complete state — consumers replace, not merge.
    var tasks: AsyncStream<[TransferTask]> { get }
}