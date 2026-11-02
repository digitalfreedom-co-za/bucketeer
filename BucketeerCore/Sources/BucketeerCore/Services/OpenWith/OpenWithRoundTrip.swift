//
//  OpenWithRoundTrip.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation
import CryptoKit

public struct RemoteObjectRef: Sendable, Hashable {
    public let accountID: UUID
    public let bucket: String
    public let key: String

    public init(accountID: UUID, bucket: String, key: String) {
        self.accountID = accountID
        self.bucket = bucket
        self.key = key
    }

    func withKey(_ key: String) -> RemoteObjectRef {
        RemoteObjectRef(accountID: accountID, bucket: bucket, key: key)
    }
}

public enum ConditionalUploadResult: Sendable, Equatable {
    /// `etag` is the one the write itself answered with (the version of
    /// exactly the uploaded bytes); `nil` when the provider sent none.
    case uploaded(etag: String?)
    /// The server refused the write because its precondition no longer
    /// held (HTTP 412, or the object already exists for `.ifAbsent`).
    case preconditionFailed
}

/// What the round-trip needs from the storage side. The host backs it
/// with the browser (HEAD) and the transfer queue (upload), so uploads
/// take the normal path including client-side encryption.
public protocol OpenWithRemote: Sendable {
    /// The object's current ETag, or `nil` when it no longer exists.
    func currentETag(of object: RemoteObjectRef) async throws -> String?
    /// Uploads `localURL`; the server must only accept the write while
    /// `precondition` holds.
    func upload(
        _ localURL: URL,
        to object: RemoteObjectRef,
        precondition: WritePrecondition
    ) async throws -> ConditionalUploadResult
}

public enum RoundTripOutcome: Sendable, Equatable {
    /// Content equals what was last downloaded or uploaded.
    case unchanged
    case uploaded(key: String)
    /// The object changed on the server since it was opened; the edit
    /// went up as a separate copy and the original was left alone.
    case conflict(copyKey: String)
}

/// Brings edits of a downloaded object back to the server without ever
/// overwriting a newer server version. Each opened file remembers the
/// ETag it was based on; a save is uploaded with If-Match on that ETag,
/// and anything else (changed, deleted, 412) becomes a conflict copy.
public actor OpenWithRoundTrip {
    private struct Session {
        var object: RemoteObjectRef
        /// Unquoted; `nil` when the server gave none.
        var etag: String?
        var digest: Data
    }

    private let remote: any OpenWithRemote
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone
    private let tag: @Sendable () -> String
    private var sessions: [URL: Session] = [:]
    /// Last sync per file. A new sync waits for it so two saves in a row
    /// never race each other's ETag.
    private var tails: [URL: Task<RoundTripOutcome, Error>] = [:]

    public init(
        remote: any OpenWithRemote,
        now: @escaping @Sendable () -> Date = Date.init,
        timeZone: TimeZone = .current,
        tag: @escaping @Sendable () -> String = ConflictCopyName.randomTag
    ) {
        self.remote = remote
        self.now = now
        self.timeZone = timeZone
        self.tag = tag
    }

    /// Starts tracking a freshly downloaded file. `etag` is the ETag the
    /// download was based on.
    public func register(localURL: URL, object: RemoteObjectRef, etag: String?) throws {
        sessions[localURL.standardizedFileURL] = Session(
            object: object,
            etag: etag.map(ETag.normalized),
            digest: try Self.digest(of: localURL)
        )
    }

    public func unregister(localURL: URL) {
        let url = localURL.standardizedFileURL
        sessions.removeValue(forKey: url)
        tails.removeValue(forKey: url)
    }

    /// The object a tracked file currently writes to (the conflict copy
    /// after a conflict).
    public func object(for localURL: URL) -> RemoteObjectRef? {
        sessions[localURL.standardizedFileURL]?.object
    }

    public func syncChanges(at localURL: URL) async throws -> RoundTripOutcome {
        let url = localURL.standardizedFileURL
        let previous = tails[url]
        let task = Task {
            _ = try? await previous?.value
            return try await self.performSync(url)
        }
        tails[url] = task
        return try await task.value
    }

    private func performSync(_ url: URL) async throws -> RoundTripOutcome {
        guard var session = sessions[url] else { return .unchanged }
        let digest = try Self.digest(of: url)
        guard digest != session.digest else { return .unchanged }

        // The next base is the ETag the write answered with. A HEAD
        // afterwards could already see somebody else's newer version
        // and would make the next save overwrite it.
        let current = try await remote.currentETag(of: session.object)
        if let base = session.etag, ETag.matches(base: base, current: current),
           case .uploaded(let written) = try await remote.upload(url, to: session.object, precondition: .ifMatch(base)) {
            session.etag = written.map(ETag.normalized)
            session.digest = digest
            store(session, for: url)
            return .uploaded(key: session.object.key)
        }

        let original = session.object
        let copy = try await ConflictCopyName.create(
            copyOf: original.key,
            date: now(),
            timeZone: timeZone,
            tag: tag
        ) { key -> String?? in
            switch try await remote.upload(url, to: original.withKey(key), precondition: .ifAbsent) {
            case .uploaded(let written): return .some(written)
            case .preconditionFailed: return .none
            }
        }
        session.object = original.withKey(copy.key)
        session.etag = copy.written.map(ETag.normalized)
        session.digest = digest
        store(session, for: url)
        return .conflict(copyKey: copy.key)
    }

    /// Keeps the result only while the file is still tracked; a file
    /// closed during the upload stays closed.
    private func store(_ session: Session, for url: URL) {
        guard sessions[url] != nil else { return }
        sessions[url] = session
    }

    private static func digest(of url: URL) throws -> Data {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return Data(SHA256.hash(data: data))
    }
}
