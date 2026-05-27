//
//  S3AccountRecord.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation
import SwiftData

/// Persistent backing for `S3Account`. Kept private to `AccountStore` —
/// callers receive `S3Account` value snapshots that are safe to cross
/// actor boundaries.
@Model
public final class S3AccountRecord {
    @Attribute(.unique) public var id: UUID
    var name: String
    public var providerRaw: String
    var region: String
    var endpointOverrideRaw: String?
    var accountID: String?
    var defaultBucket: String?
    public var usesPathStyle: Bool
    var lastUsedAt: Date?
    var sortIndex: Int

    init(
        id: UUID,
        name: String,
        providerRaw: String,
        region: String,
        endpointOverrideRaw: String?,
        accountID: String?,
        defaultBucket: String?,
        usesPathStyle: Bool,
        lastUsedAt: Date?,
        sortIndex: Int
    ) {
        self.id = id
        self.name = name
        self.providerRaw = providerRaw
        self.region = region
        self.endpointOverrideRaw = endpointOverrideRaw
        self.accountID = accountID
        self.defaultBucket = defaultBucket
        self.usesPathStyle = usesPathStyle
        self.lastUsedAt = lastUsedAt
        self.sortIndex = sortIndex
    }

    convenience init(account: S3Account, sortIndex: Int = 0) {
        self.init(
            id: account.id,
            name: account.name,
            providerRaw: account.provider.rawValue,
            region: account.region,
            endpointOverrideRaw: account.endpointOverride?.absoluteString,
            accountID: account.accountID,
            defaultBucket: account.defaultBucket,
            usesPathStyle: account.usesPathStyle,
            lastUsedAt: account.lastUsedAt,
            sortIndex: sortIndex
        )
    }

    func update(from account: S3Account) {
        name = account.name
        providerRaw = account.provider.rawValue
        region = account.region
        endpointOverrideRaw = account.endpointOverride?.absoluteString
        accountID = account.accountID
        defaultBucket = account.defaultBucket
        usesPathStyle = account.usesPathStyle
        lastUsedAt = account.lastUsedAt
    }

    /// Sendable value snapshot of this record.
    var snapshot: S3Account {
        S3Account(
            id: id,
            name: name,
            provider: S3Provider(rawValue: providerRaw) ?? .custom,
            region: region,
            endpointOverride: endpointOverrideRaw.flatMap { URL(string: $0) },
            accountID: accountID,
            defaultBucket: defaultBucket,
            usesPathStyle: usesPathStyle,
            lastUsedAt: lastUsedAt
        )
    }
}
