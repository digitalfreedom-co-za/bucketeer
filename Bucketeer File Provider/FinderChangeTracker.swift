//
//  FinderChangeTracker.swift
//  Bucketeer File Provider
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation
import BucketeerCore

/// Persists one `FinderChangeState` per mounted bucket in the
/// extension's own Application Support folder and turns fresh listings
/// into change reports for the working set.
actor FinderChangeTracker {
    static let shared = FinderChangeTracker()

    struct Changes {
        let updated: [S3Object]
        let deleted: [String]
        let anchor: String
    }

    enum TrackerError: Error {
        /// The system's anchor is not the one we hold (state lost or
        /// superseded); it has to enumerate again.
        case anchorExpired
    }

    /// Lists one folder level (all pages) of the mounted bucket.
    typealias Lister = @Sendable (_ prefix: String) async throws -> [S3Object]

    func track(prefix: String, domain: String) {
        var state = load(domain) ?? FinderChangeState(anchor: Self.newAnchor())
        if state.track(prefix: prefix) {
            save(state, domain: domain)
        }
    }

    /// The anchor of the remembered listing; takes a first listing when
    /// there is none yet.
    func currentAnchor(domain: String, list: Lister) async throws -> String {
        if let state = load(domain) { return state.anchor }
        var state = FinderChangeState(anchor: Self.newAnchor())
        let listing = try await snapshot(of: state.trackedPrefixes, list: list)
        _ = state.advance(to: listing.entries, anchor: Self.newAnchor())
        save(state, domain: domain)
        return state.anchor
    }

    func changes(since anchor: String, domain: String, list: Lister) async throws -> Changes {
        guard var state = load(domain), state.anchor == anchor else {
            throw TrackerError.anchorExpired
        }
        let listing = try await snapshot(of: state.trackedPrefixes, list: list)
        let diff = state.advance(to: listing.entries, anchor: Self.newAnchor())
        save(state, domain: domain)
        return Changes(
            updated: diff.updated.compactMap { listing.objects[$0] },
            deleted: diff.deleted,
            anchor: state.anchor
        )
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
        return (objects.mapValues { $0.isFolder ? "" : $0.etag }, objects)
    }

    // MARK: - Storage

    private static func newAnchor() -> String { UUID().uuidString }

    private func fileURL(_ domain: String) -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let safeName = Data(domain.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
        return support
            .appending(path: "ChangeTracking", directoryHint: .isDirectory)
            .appending(path: "\(safeName).json")
    }

    private func load(_ domain: String) -> FinderChangeState? {
        guard let url = fileURL(domain), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FinderChangeState.self, from: data)
    }

    /// A failed write only costs a full re-enumeration later (the next
    /// anchor check fails), so it is not an error for the caller.
    private func save(_ state: FinderChangeState, domain: String) {
        guard let url = fileURL(domain), let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }
}
