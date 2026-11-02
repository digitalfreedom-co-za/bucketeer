//
//  BucketInsights.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation

/// One lifecycle rule on a bucket. Phase 13.9. Read-only in v1 — the
/// editor lands in a later phase, this one just surfaces what's
/// already configured.
public struct LifecycleRule: Identifiable, Hashable, Sendable {
    public let id: String
    public let prefix: String?
    public let enabled: Bool
    /// "Transition after X days into storage class Y" summaries — one
    /// per transition rule.
    public let transitions: [String]
    /// "Expire after X days" / "Expire non-current after X days"
    /// summaries.
    public let expirations: [String]

    public init(
        id: String,
        prefix: String?,
        enabled: Bool,
        transitions: [String],
        expirations: [String]
    ) {
        self.id = id
        self.prefix = prefix
        self.enabled = enabled
        self.transitions = transitions
        self.expirations = expirations
    }
}

/// One CORS rule on a bucket. Phase 13.9.
public struct CORSRule: Identifiable, Hashable, Sendable {
    public let id: String
    public let allowedOrigins: [String]
    public let allowedMethods: [String]
    public let allowedHeaders: [String]
    public let exposeHeaders: [String]
    public let maxAgeSeconds: Int?

    public init(
        id: String,
        allowedOrigins: [String],
        allowedMethods: [String],
        allowedHeaders: [String],
        exposeHeaders: [String],
        maxAgeSeconds: Int?
    ) {
        self.id = id
        self.allowedOrigins = allowedOrigins
        self.allowedMethods = allowedMethods
        self.allowedHeaders = allowedHeaders
        self.exposeHeaders = exposeHeaders
        self.maxAgeSeconds = maxAgeSeconds
    }
}

/// Aggregate bucket-configuration snapshot. Phase 13.9. Each field is
/// "optional via an empty value": empty arrays mean no rules,
/// `policyJSON == nil` means no policy attached. The view surfaces a
/// "none configured" placeholder for each section.
public struct BucketInsights: Hashable, Sendable {
    public let bucket: String
    public let lifecycleRules: [LifecycleRule]
    public let corsRules: [CORSRule]
    /// Bucket policy serialised as pretty-printed JSON (or `nil`).
    public let policyJSON: String?
    public let collectedAt: Date

    public init(
        bucket: String,
        lifecycleRules: [LifecycleRule],
        corsRules: [CORSRule],
        policyJSON: String?,
        collectedAt: Date = Date()
    ) {
        self.bucket = bucket
        self.lifecycleRules = lifecycleRules
        self.corsRules = corsRules
        self.policyJSON = policyJSON
        self.collectedAt = collectedAt
    }
}
