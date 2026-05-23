//
//  S3Account.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation

/// Non-secret connection metadata for one configured S3 endpoint. Lives
/// in the SwiftData store in the shared App Group container. The matching
/// secret (`AccountCredentials`) lives in the Keychain, keyed by `id`.
public struct S3Account: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var provider: S3Provider
    public var region: String
    public var endpointOverride: URL?
    public var accountID: String?
    public var defaultBucket: String?
    public var usesPathStyle: Bool
    public var lastUsedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        provider: S3Provider,
        region: String? = nil,
        endpointOverride: URL? = nil,
        accountID: String? = nil,
        defaultBucket: String? = nil,
        usesPathStyle: Bool? = nil,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.region = region ?? provider.defaultRegion
        self.endpointOverride = endpointOverride
        self.accountID = accountID
        self.defaultBucket = defaultBucket
        self.usesPathStyle = usesPathStyle ?? provider.usesPathStyleByDefault
        self.lastUsedAt = lastUsedAt
    }
}

/// Credentials for one account. Persisted in the macOS Keychain; never
/// written to disk in plaintext, never logged.
public struct AccountCredentials: Codable, Hashable, Sendable {
    public let accessKey: String
    public let secretKey: String
    public let sessionToken: String?

    public init(accessKey: String, secretKey: String, sessionToken: String? = nil) {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.sessionToken = sessionToken
    }
}
