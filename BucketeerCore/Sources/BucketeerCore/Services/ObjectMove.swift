//
//  ObjectMove.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation

/// Moves one object inside a bucket by copy and delete without losing
/// data: the copy is create-only and reads only the version `etag`,
/// and the source is deleted only while it is still that version.
public enum ObjectMove {

    /// Throws `.preconditionFailed` when `newKey` is taken or the source
    /// is no longer `etag`; nothing changed then. Returns `false` when
    /// the copy exists but the source changed afterwards and was kept.
    public static func move(
        _ key: String,
        etag: String,
        to newKey: String,
        browser: any S3Browsing,
        account: S3Account,
        bucket: String
    ) async throws -> Bool {
        try await browser.copyIfAbsent(account: account, bucket: bucket, fromKey: key, sourceETag: etag, toKey: newKey)
        return try await browser.deleteIfUnchanged(account: account, bucket: bucket, key: key, etag: etag)
    }
}
