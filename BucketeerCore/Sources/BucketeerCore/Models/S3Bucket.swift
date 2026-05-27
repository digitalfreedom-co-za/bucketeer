//
//  S3Bucket.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation

/// One bucket as returned by `ListBuckets`. `region` is reported by
/// providers that include `LocationConstraint`; many do not.
public struct S3Bucket: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let createdAt: Date?
    public let region: String?

    public init(name: String, createdAt: Date?, region: String?) {
        self.name = name
        self.createdAt = createdAt
        self.region = region
    }
}
