//
//  StagedDownload.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation

/// Downloads land in a staging file and replace the destination only
/// once they are complete. A failed GET, a cancel, a full disk or a
/// failed decryption therefore leaves the existing file as it was.
///
/// The staging file sits in the item-replacement directory the system
/// picks for the destination's volume (the mechanism document saves use
/// in the sandbox), so publishing is an atomic `replaceItemAt`.
public enum StagedDownload {

    /// Runs `body` against a fresh staging file and publishes it to
    /// `destination` when `body` returns. Any error discards the
    /// staging file and is rethrown; `destination` stays intact.
    public static func write<T>(
        to destination: URL,
        _ body: (URL) async throws -> T
    ) async throws -> T {
        let staging = stagingURL(for: destination)
        do {
            let result = try await body(staging)
            // A cancel that arrives with the last bytes must not publish.
            try Task.checkCancellation()
            try publish(staging, to: destination)
            return result
        } catch {
            discard(staging)
            throw error
        }
    }

    /// A not-yet-existing file in its own staging folder, preferably on
    /// the destination's volume.
    public static func stagingURL(for destination: URL) -> URL {
        let folder = replacementDirectory(for: destination)
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("BucketeerStaging-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(destination.lastPathComponent.isEmpty ? "download" : destination.lastPathComponent)
    }

    /// Moves the staged file to `destination`, replacing an existing
    /// file atomically, then removes the staging folder.
    public static func publish(_ staging: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: destination)
        }
        try? FileManager.default.removeItem(at: staging.deletingLastPathComponent())
    }

    public static func discard(_ staging: URL) {
        try? FileManager.default.removeItem(at: staging.deletingLastPathComponent())
    }

    private static func replacementDirectory(for destination: URL) -> URL? {
        // The destination itself may not exist yet; its folder decides
        // the volume just as well.
        for candidate in [destination, destination.deletingLastPathComponent()] {
            if let folder = try? FileManager.default.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: candidate,
                create: true
            ) {
                return folder
            }
        }
        return nil
    }
}
