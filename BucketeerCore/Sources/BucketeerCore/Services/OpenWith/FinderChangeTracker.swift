//
//  FinderChangeTracker.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation

/// Persists one `FinderChangeState` per mounted bucket and turns fresh
/// listings into change reports for the working set.
///
/// Listing suspends, and the actor accepts other calls meanwhile (a
/// folder enumeration recording its items, a second change request).
/// So nothing read before an await is written back blindly: a change
/// request re-reads the state before it commits, gives up when its
/// anchor was superseded or it was cancelled, and lists again when
/// items were recorded in between.
public actor FinderChangeTracker {
    public struct Changes: Sendable {
        public let updated: [S3Object]
        public let deleted: [String]
        public let anchor: String
    }

    public enum TrackerError: Error {
        /// The system's anchor is not the one we hold (state lost or
        /// superseded); it has to enumerate again.
        case anchorExpired
    }

    /// Lists one folder level (all pages) of the mounted bucket.
    public typealias Lister = @Sendable (_ prefix: String) async throws -> [S3Object]

    /// Listings taken before giving up because folder enumerations kept
    /// recording items meanwhile; the system then re-enumerates.
    static let maxAttempts = 3

    private let storageDirectory: URL

    public init(storageDirectory: URL) {
        self.storageDirectory = storageDirectory
    }

    /// One page of a folder enumeration was delivered to the system.
    public func record(_ objects: [S3Object], under prefix: String, domain: String) {
        var state = load(domain) ?? FinderChangeState(anchor: Self.newAnchor())
        state.record(Self.entries(of: objects, excluding: prefix), under: prefix)
        save(state, domain: domain)
    }

    /// The anchor of the remembered listing; takes a first listing when
    /// there is none yet.
    public func currentAnchor(domain: String, list: Lister) async throws -> String {
        if let state = load(domain) { return state.anchor }
        var fresh = FinderChangeState(anchor: Self.newAnchor())
        let prefixes = fresh.trackedPrefixes
        let listing = try await snapshot(of: prefixes, list: list)
        // Another call may have created the state during the listing;
        // its anchor is the one to hand out.
        if let state = load(domain) { return state.anchor }
        _ = fresh.advance(to: listing.entries, listedPrefixes: prefixes, anchor: Self.newAnchor())
        save(fresh, domain: domain)
        return fresh.anchor
    }

    public func changes(since anchor: String, domain: String, list: Lister) async throws -> Changes {
        for _ in 0..<Self.maxAttempts {
            guard let start = load(domain), start.anchor == anchor else {
                throw TrackerError.anchorExpired
            }
            let prefixes = start.trackedPrefixes
            let listing = try await snapshot(of: prefixes, list: list)
            try Task.checkCancellation()

            // No await from here to the save: this is the commit.
            guard var state = load(domain), state.anchor == anchor else {
                throw TrackerError.anchorExpired
            }
            guard state.revision == start.revision else { continue }
            let diff = state.advance(to: listing.entries, listedPrefixes: prefixes, anchor: Self.newAnchor())
            save(state, domain: domain)
            return Changes(
                updated: diff.updated.compactMap { listing.objects[$0] },
                deleted: diff.deleted,
                anchor: state.anchor
            )
        }
        throw TrackerError.anchorExpired
    }

    // MARK: - Listing

    private func snapshot(
        of prefixes: Set<String>,
        list: Lister
    ) async throws -> (entries: [String: String], objects: [String: S3Object]) {
        var objects: [String: S3Object] = [:]
        for prefix in prefixes {
            for object in try await list(prefix) where object.key != prefix {
                objects[object.key] = object
            }
        }
        return (Self.entries(of: Array(objects.values), excluding: nil), objects)
    }

    private static func entries(of objects: [S3Object], excluding prefix: String?) -> [String: String] {
        Dictionary(
            objects.filter { $0.key != prefix }.map { ($0.key, $0.isFolder ? "" : $0.etag) },
            uniquingKeysWith: { _, last in last }
        )
    }

    // MARK: - Storage

    private static func newAnchor() -> String { UUID().uuidString }

    private func fileURL(_ domain: String) -> URL {
        let safeName = Data(domain.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
        return storageDirectory.appending(path: "\(safeName).json")
    }

    private func load(_ domain: String) -> FinderChangeState? {
        guard let data = try? Data(contentsOf: fileURL(domain)) else { return nil }
        return try? JSONDecoder().decode(FinderChangeState.self, from: data)
    }

    /// A failed write only costs a full re-enumeration later (the next
    /// anchor check fails), so it is not an error for the caller.
    private func save(_ state: FinderChangeState, domain: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(domain), options: .atomic)
    }
}
