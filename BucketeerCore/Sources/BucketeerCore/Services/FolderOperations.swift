//
//  FolderOperations.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation

/// Folder actions on an object store, where a folder is only a key
/// prefix. Each action works on every object below the prefix; the
/// `folder/` marker, if there is one, is handled like the rest.
public enum FolderOperations {

    /// Snapshot of a folder: the objects below it as listed (their ETags
    /// identify the versions a move may delete) and every folder prefix,
    /// the folder itself first.
    public struct Contents: Sendable {
        public let prefix: String
        public let files: [S3Object]
        public let folders: [String]
    }

    public static func contents(
        of prefix: String,
        browser: any S3Browsing,
        account: S3Account,
        bucket: String
    ) async throws -> Contents {
        var files: [S3Object] = []
        var folders: [String] = [prefix]
        var queue: [String] = [prefix]
        while !queue.isEmpty {
            let scope = queue.removeFirst()
            var token: String?
            repeat {
                try Task.checkCancellation()
                let page = try await browser.listObjects(
                    account: account, bucket: bucket, prefix: scope, continuationToken: token
                )
                for object in page.objects where object.key != scope {
                    if object.isFolder {
                        folders.append(object.key)
                        queue.append(object.key)
                    } else {
                        files.append(object)
                    }
                }
                token = page.hasMore ? page.continuationToken : nil
            } while token != nil
        }
        return Contents(prefix: prefix, files: files, folders: folders)
    }

    /// Deletes every object of the folder, then the folder markers
    /// (deepest first) so an interrupted delete leaves the tree visible.
    public static func delete(
        _ contents: Contents,
        browser: any S3Browsing,
        account: S3Account,
        bucket: String
    ) async throws {
        try Task.checkCancellation()
        try await browser.delete(account: account, bucket: bucket, keys: contents.files.map(\.key))
        try await deleteMarkers(contents.folders.reversed(), browser: browser, account: account, bucket: bucket)
    }

    /// Moves the folder to `newPrefix`: copies everything first, then
    /// deletes each source only while it is still the version that was
    /// copied. Refuses a destination that already holds objects, so
    /// nothing is overwritten. Returns the source keys kept because they
    /// changed during the move.
    public static func move(
        _ contents: Contents,
        to newPrefix: String,
        browser: any S3Browsing,
        account: S3Account,
        bucket: String
    ) async throws -> [String] {
        let destination = try await browser.listObjects(
            account: account, bucket: bucket, prefix: newPrefix, continuationToken: nil
        )
        let markerExists = try await exists(newPrefix, browser: browser, account: account, bucket: bucket)
        guard destination.objects.isEmpty, !markerExists else {
            throw BucketeerError.preconditionFailed(key: newPrefix)
        }
        let relocate = { (key: String) in newPrefix + key.dropFirst(contents.prefix.count) }
        for file in contents.files {
            try Task.checkCancellation()
            try await browser.copy(
                account: account, fromBucket: bucket, fromKey: file.key,
                toBucket: bucket, toKey: relocate(file.key), metadata: nil
            )
        }
        for folder in contents.folders {
            do {
                try await browser.copy(
                    account: account, fromBucket: bucket, fromKey: folder,
                    toBucket: bucket, toKey: relocate(folder), metadata: nil
                )
            } catch BucketeerError.objectNotFound {
                // A folder that exists only through its objects.
            }
        }
        var kept: [String] = []
        for file in contents.files {
            if try await !browser.deleteIfUnchanged(account: account, bucket: bucket, key: file.key, etag: file.etag) {
                kept.append(file.key)
            }
        }
        try await deleteMarkers(contents.folders.reversed(), browser: browser, account: account, bucket: bucket)
        return kept
    }

    private static func deleteMarkers(
        _ folders: some Sequence<String>,
        browser: any S3Browsing,
        account: S3Account,
        bucket: String
    ) async throws {
        for folder in folders {
            guard try await exists(folder, browser: browser, account: account, bucket: bucket) else { continue }
            try await browser.delete(account: account, bucket: bucket, keys: [folder])
        }
    }

    private static func exists(
        _ key: String,
        browser: any S3Browsing,
        account: S3Account,
        bucket: String
    ) async throws -> Bool {
        do {
            _ = try await browser.head(account: account, bucket: bucket, key: key)
            return true
        } catch BucketeerError.objectNotFound {
            return false
        }
    }
}
