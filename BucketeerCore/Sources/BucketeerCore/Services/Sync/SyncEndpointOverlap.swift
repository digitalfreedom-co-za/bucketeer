//
//  SyncEndpointOverlap.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation

/// Refuses sync jobs whose source and destination contain each other.
/// Syncing a scope into its own child nests a new copy on every run;
/// mirroring a child into its parent sees the source files as
/// destination orphans and deletes them.
public enum SyncEndpointOverlap {

    /// Throws when the endpoints overlap. Local folders are compared by
    /// their resolved roots (`sourceRoot` / `destinationRoot`, after the
    /// bookmarks were resolved), so a symlink cannot hide the overlap.
    public static func validate(
        source: SyncEndpoint,
        destination: SyncEndpoint,
        sourceRoot: URL? = nil,
        destinationRoot: URL? = nil
    ) throws {
        if overlaps(source, destination) || overlaps(sourceRoot, destinationRoot) {
            throw BucketeerError.unknown(message: String(
                localized: "sync.error.overlappingEndpoints",
                defaultValue: "The source and the destination of this sync job contain each other. Choose folders that are separate, so the job neither copies into itself nor deletes its own source."
            ))
        }
    }

    private static func overlaps(_ first: SyncEndpoint, _ second: SyncEndpoint) -> Bool {
        guard case .s3(let firstAccount, let firstBucket, let firstPrefix) = first,
              case .s3(let secondAccount, let secondBucket, let secondPrefix) = second,
              firstAccount == secondAccount, firstBucket == secondBucket
        else { return false }
        // A prefix selects every key that starts with it, so `photos`
        // also covers `photos-raw/`.
        return firstPrefix.hasPrefix(secondPrefix) || secondPrefix.hasPrefix(firstPrefix)
    }

    private static func overlaps(_ first: URL?, _ second: URL?) -> Bool {
        guard let first, let second else { return false }
        // One path is an ancestor of (or equal to) the other when the
        // shorter one is a prefix of the longer. Case-insensitive on
        // purpose: the default macOS volume format treats `Photos` and
        // `photos` as one folder.
        return zip(components(of: first), components(of: second))
            .allSatisfy { $0.caseInsensitiveCompare($1) == .orderedSame }
    }

    private static func components(of url: URL) -> [String] {
        url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            .map(\.precomposedStringWithCanonicalMapping)
    }
}
