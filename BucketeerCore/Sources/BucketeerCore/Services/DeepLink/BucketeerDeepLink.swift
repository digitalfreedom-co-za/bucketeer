//
//  BucketeerDeepLink.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation

/// Typed `bucketeer://` deep links. Phase 13.11.
///
/// Grammar (host segment selects the destination, path segments
/// carry the identifying components):
///
/// - `bucketeer://account/<accountUUID>`
/// - `bucketeer://bucket/<accountUUID>/<bucket>[/<prefix>…]`
/// - `bucketeer://object/<accountUUID>/<bucket>/<key…>`
/// - `bucketeer://sync/<jobUUID>`
/// - `bucketeer://activity`
/// - `bucketeer://trash`
///
/// Stable in v1 — the routing layer holds users by URL, so changes
/// must be additive (new hosts) rather than breaking.
public enum BucketeerDeepLink: Hashable, Sendable {
    case account(id: UUID)
    case bucket(accountID: UUID, bucket: String, prefix: String)
    case object(accountID: UUID, bucket: String, key: String)
    case syncJob(id: UUID)
    case activity
    case trash

    public static let scheme = "bucketeer"

    /// Parse a URL. Returns `nil` for anything that isn't a
    /// `bucketeer://` URL or doesn't match the grammar.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        guard let host = url.host?.lowercased() else { return nil }
        // The URL.pathComponents call returns "/" as the first
        // element when the URL has any path; strip that so positions
        // line up with what the grammar expects.
        let raw = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "account":
            // Codex audit R2 (medium): require an exact 1-component
            // path so `bucketeer://account/<uuid>/garbage` doesn't
            // route as a valid link with the garbage silently
            // dropped.
            guard raw.count == 1,
                  let first = raw.first,
                  let id = UUID(uuidString: first) else { return nil }
            self = .account(id: id)
        case "bucket":
            guard raw.count >= 2,
                  let id = UUID(uuidString: raw[0]) else { return nil }
            let bucket = raw[1]
            let prefixComponents = raw.dropFirst(2)
            let prefix = prefixComponents.isEmpty
                ? ""
                : prefixComponents.joined(separator: "/") + "/"
            self = .bucket(accountID: id, bucket: bucket, prefix: prefix)
        case "object":
            guard raw.count >= 3,
                  let id = UUID(uuidString: raw[0]) else { return nil }
            let bucket = raw[1]
            let key = raw.dropFirst(2).joined(separator: "/")
            self = .object(accountID: id, bucket: bucket, key: key)
        case "sync":
            guard raw.count == 1,
                  let first = raw.first,
                  let id = UUID(uuidString: first) else { return nil }
            self = .syncJob(id: id)
        case "activity":
            guard raw.isEmpty else { return nil }
            self = .activity
        case "trash":
            guard raw.isEmpty else { return nil }
            self = .trash
        default:
            return nil
        }
    }

    /// Render this link back into a URL. Round-trips through `init?`
    /// for every case.
    public var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .account(let id):
            components.host = "account"
            components.path = "/" + id.uuidString
        case .bucket(let id, let bucket, let prefix):
            components.host = "bucket"
            var path = "/" + id.uuidString + "/" + bucket
            if !prefix.isEmpty {
                let trimmed = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
                path += "/" + trimmed
            }
            components.path = path
        case .object(let id, let bucket, let key):
            components.host = "object"
            components.path = "/" + id.uuidString + "/" + bucket + "/" + key
        case .syncJob(let id):
            components.host = "sync"
            components.path = "/" + id.uuidString
        case .activity:
            components.host = "activity"
        case .trash:
            components.host = "trash"
        }
        return components.url
    }
}
