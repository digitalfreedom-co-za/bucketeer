//
//  EncryptedBucketList.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation

/// The buckets that use client-side encryption, mirrored by the host
/// into the App Group container. The File Provider extension moves raw
/// bytes and cannot read the host-only key store, so it checks this
/// list and refuses encrypted buckets even if a domain for one exists.
///
/// Entries use the File Provider domain identifier format
/// `"<accountID.uuidString>::<bucket>"`.
public enum EncryptedBucketList {
    public static func url(inGroupContainer groupURL: URL) -> URL {
        groupURL.appending(path: AppEnvironment.encryptedBucketListFileName)
    }

    public static func entry(accountID: UUID, bucket: String) -> String {
        "\(accountID.uuidString)::\(bucket)"
    }

    public static func write(_ keys: [BucketEncryptionKey], to url: URL) throws {
        let entries = keys.map { entry(accountID: $0.accountID, bucket: $0.bucket) }.sorted()
        try JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }

    /// Throws when the list is missing or unreadable, so the caller can
    /// fail closed: without the list nobody can tell whether a bucket
    /// is encrypted.
    public static func contains(domainIdentifier: String, at url: URL) throws -> Bool {
        let entries = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        return entries.contains(domainIdentifier)
    }
}
