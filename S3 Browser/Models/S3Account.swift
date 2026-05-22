//
//  S3Account.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation

/// Non-secret connection metadata for one configured S3 endpoint. Lives
/// in the SwiftData store in the shared App Group container. The matching
/// secret (`AccountCredentials`) lives in the Keychain, keyed by `id`.
struct S3Account: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var provider: S3Provider
    var region: String
    var endpointOverride: URL?
    var accountID: String?
    var defaultBucket: String?
    var usesPathStyle: Bool
    var lastUsedAt: Date?

    init(
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
struct AccountCredentials: Codable, Hashable, Sendable {
    let accessKey: String
    let secretKey: String
    let sessionToken: String?

    init(accessKey: String, secretKey: String, sessionToken: String? = nil) {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.sessionToken = sessionToken
    }
}
