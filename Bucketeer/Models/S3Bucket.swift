//
//  S3Bucket.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation

/// One bucket as returned by `ListBuckets`. `region` is reported by
/// providers that include `LocationConstraint`; many do not.
struct S3Bucket: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let createdAt: Date?
    let region: String?
}
