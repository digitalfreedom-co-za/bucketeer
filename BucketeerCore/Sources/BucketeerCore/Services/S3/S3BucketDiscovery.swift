//
//  S3BucketDiscovery.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
@preconcurrency import SotoS3

/// Decides which buckets an S3 account shows. Keys scoped to one
/// bucket (common on Civo) may not call ListBuckets, so an account
/// that names its bucket checks that bucket directly and shows only
/// it. Errors leave as `BucketeerError`, explained for the account.
enum S3BucketDiscovery {

    static func buckets(
        for account: S3Account,
        listAll: () async throws -> [S3Bucket],
        probe: (String) async throws -> Void
    ) async throws -> [S3Bucket] {
        if let name = account.namedBucket {
            do {
                try await probe(name)
            } catch {
                throw S3Service.map(error, bucket: name, account: account)
            }
            return [S3Bucket(name: name, createdAt: nil, region: nil)]
        }
        do {
            return try await listAll()
        } catch {
            if let s3Error = error as? S3ErrorType,
               s3Error.errorCode == S3ErrorType.accessDenied.errorCode {
                throw BucketeerError.bucketListingDenied
            }
            throw S3Service.map(error, account: account)
        }
    }
}

extension S3Account {
    /// The bucket the user entered for the account, if any.
    public var namedBucket: String? {
        let trimmed = defaultBucket?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
