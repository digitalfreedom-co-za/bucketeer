//
//  MountedBucket.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import CryptoKit
import Foundation

/// Moves file contents between the File Provider extension and one
/// bucket. The extension supplies it per provider (Azure transporter,
/// S3 direct fetch).
public protocol MountedContentTransport: Sendable {
    /// Writes the file to `key`; with a precondition only while it
    /// holds (`.preconditionFailed` otherwise). Returns the new ETag.
    func upload(_ url: URL, to key: String, precondition: WritePrecondition?) async throws -> String?
    /// Reads `key` only while it is the version `etag`
    /// (`.preconditionFailed` otherwise), so the bytes match the item
    /// metadata reported with them.
    func download(_ key: String, matching etag: String, size: Int64, to url: URL) async throws
}

/// The version rules of a mounted bucket. Every Finder change is
/// applied only against the server version Finder based it on: a
/// newer or colliding object is never overwritten or deleted. Where
/// the change cannot be applied as asked, the result says so
/// (`isConflict`) so the extension can tell the user.
public struct MountedBucket: Sendable {

    /// Why a Finder change was not applied.
    public enum Refusal: Error, Equatable {
        /// The server object changed since the version Finder knew.
        case changedOnServer
        /// The requested content version is gone from the server.
        case versionUnavailable
    }

    /// Where Finder's item ended up.
    public struct Placement: Sendable, Equatable {
        public let object: S3Object
        /// The server differed from what Finder expected: the change
        /// went to a conflict copy, or the item stayed as it was.
        public let isConflict: Bool
    }

    private let browser: any S3Browsing
    private let account: S3Account
    private let bucket: String
    private let transport: any MountedContentTransport

    public init(browser: any S3Browsing, account: S3Account, bucket: String, transport: any MountedContentTransport) {
        self.browser = browser
        self.account = account
        self.bucket = bucket
        self.transport = transport
    }

    // MARK: - Fetch

    /// Downloads the current version — or exactly `requestedVersion` —
    /// and returns the metadata of the version that was read.
    public func fetch(_ key: String, requestedVersion: String?, to url: URL) async throws -> S3Object {
        let object = try await head(key)
        if let requestedVersion, !ETag.matches(base: requestedVersion, current: object.etag) {
            throw Refusal.versionUnavailable
        }
        do {
            try await transport.download(key, matching: object.etag, size: object.size, to: url)
            return object
        } catch BucketeerError.preconditionFailed {
            // Replaced between HEAD and GET.
            guard requestedVersion == nil else { throw Refusal.versionUnavailable }
            let latest = try await head(key)
            try await transport.download(key, matching: latest.etag, size: latest.size, to: url)
            return latest
        }
    }

    // MARK: - Create

    /// Creates `key` only if it is free. When something is there, an
    /// identical object (re-import after a domain reset) is reused;
    /// anything else keeps its place and the file becomes a conflict copy.
    public func create(_ key: String, contents: URL, mayAlreadyExist: Bool) async throws -> Placement {
        do {
            _ = try await transport.upload(contents, to: key, precondition: .ifAbsent)
            return Placement(object: try await head(key), isConflict: false)
        } catch BucketeerError.preconditionFailed {
            if mayAlreadyExist, let existing = try await currentHead(key), try Self.hasSameContent(contents, as: existing) {
                return Placement(object: existing, isConflict: false)
            }
            return try await conflictCopy(of: key, contents: contents)
        }
    }

    // MARK: - Rename

    /// Renames by conditional copy and conditional delete. An outdated
    /// `baseVersion` leaves the object where it is; a taken destination
    /// name is never replaced — the object moves to a conflict-copy name
    /// beside it instead.
    public func rename(_ key: String, baseVersion: String?, to newKey: String) async throws -> Placement {
        let source = try await head(key)
        guard ETag.matches(base: baseVersion, current: source.etag) else {
            return Placement(object: source, isConflict: true)
        }
        let target: String
        let isConflict: Bool
        if try await copy(key, version: source.etag, to: newKey) {
            (target, isConflict) = (newKey, false)
        } else {
            target = try await ConflictCopyName.create(copyOf: newKey, date: Date()) { candidate -> Bool? in
                try await copy(key, version: source.etag, to: candidate) ? true : nil
            }.key
            isConflict = true
        }
        // A write that landed during the copy stays at the old key.
        let removed = try await browser.deleteIfUnchanged(account: account, bucket: bucket, key: key, etag: source.etag)
        return Placement(object: try await head(target), isConflict: isConflict || !removed)
    }

    // MARK: - Delete

    /// Deletes only the version Finder knew; a newer one is kept.
    public func delete(_ key: String, baseVersion: String?) async throws {
        guard let baseVersion,
              try await browser.deleteIfUnchanged(account: account, bucket: bucket, key: key, etag: baseVersion)
        else { throw Refusal.changedOnServer }
    }

    /// Deletes everything below `prefix`, each object only while it is
    /// still the version Finder knew (`knownVersions`, key → ETag). An
    /// object Finder never saw, or one that changed since, is kept
    /// together with every folder marker, and the delete refused.
    /// Deletes page by page, so a huge folder never sits in memory.
    public func deleteFolder(_ prefix: String, knownVersions: [String: String]) async throws {
        var folders = [prefix]
        var queue = [prefix]
        var keptChanged = false
        while !queue.isEmpty {
            let scope = queue.removeFirst()
            var token: String?
            repeat {
                try Task.checkCancellation()
                let page = try await browser.listObjects(account: account, bucket: bucket, prefix: scope, continuationToken: token)
                for object in page.objects where object.key != scope {
                    if object.isFolder {
                        folders.append(object.key)
                        queue.append(object.key)
                    } else if let known = knownVersions[object.key],
                              try await browser.deleteIfUnchanged(account: account, bucket: bucket,
                                                                  key: object.key, etag: known) {
                        continue
                    } else {
                        keptChanged = true
                    }
                }
                token = page.hasMore ? page.continuationToken : nil
            } while token != nil
        }
        guard !keptChanged else { throw Refusal.changedOnServer }
        for marker in folders.reversed() {
            guard try await currentHead(marker) != nil else { continue }
            try await browser.delete(account: account, bucket: bucket, keys: [marker])
        }
    }

    // MARK: - Helpers

    private func conflictCopy(of key: String, contents: URL) async throws -> Placement {
        let copy = try await ConflictCopyName.create(copyOf: key, date: Date()) { candidate -> Bool? in
            do {
                _ = try await transport.upload(contents, to: candidate, precondition: .ifAbsent)
                return true
            } catch BucketeerError.preconditionFailed {
                return nil
            }
        }
        return Placement(object: try await head(copy.key), isConflict: true)
    }

    /// `false` when the destination is taken; a changed source surfaces
    /// as `.changedOnServer`.
    private func copy(_ key: String, version: String, to destination: String) async throws -> Bool {
        // HEAD first: some S3-compatible providers ignore If-None-Match
        // on copies.
        guard try await currentHead(destination) == nil else { return false }
        do {
            try await browser.copyIfAbsent(account: account, bucket: bucket, fromKey: key,
                                           sourceETag: version, toKey: destination)
            return true
        } catch BucketeerError.preconditionFailed {
            if try await currentHead(destination) != nil { return false }
            throw Refusal.changedOnServer
        }
    }

    private func head(_ key: String) async throws -> S3Object {
        try await browser.head(account: account, bucket: bucket, key: key)
    }

    private func currentHead(_ key: String) async throws -> S3Object? {
        do {
            return try await head(key)
        } catch BucketeerError.objectNotFound {
            return nil
        }
    }

    /// Single-part S3 ETags are the MD5 of the bytes; other ETags (Azure,
    /// multipart) cannot prove equality, so those objects never count
    /// as the same and the file becomes a conflict copy instead.
    static func hasSameContent(_ file: URL, as object: S3Object) throws -> Bool {
        let etag = ETag.normalized(object.etag).lowercased()
        guard etag.count == 32, etag.allSatisfy(\.isHexDigit),
              let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              Int64(size) == object.size
        else { return false }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var md5 = Insecure.MD5()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            md5.update(data: chunk)
        }
        return md5.finalize().map { String(format: "%02x", $0) }.joined() == etag
    }
}
