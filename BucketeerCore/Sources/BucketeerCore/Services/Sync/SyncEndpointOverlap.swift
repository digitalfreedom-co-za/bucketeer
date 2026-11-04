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

    /// Throws when the endpoints overlap. Object-store sides are the
    /// same storage when they are the same account or, given the
    /// resolved accounts, two accounts for the same endpoint. Local
    /// folders are compared by their resolved roots (after the bookmarks
    /// were resolved), so a symlink cannot hide the overlap.
    public static func validate(
        source: SyncEndpoint,
        destination: SyncEndpoint,
        sourceAccount: S3Account? = nil,
        destinationAccount: S3Account? = nil,
        sourceRoot: URL? = nil,
        destinationRoot: URL? = nil
    ) throws {
        let sameStorage = { (first: UUID, second: UUID) in
            if first == second { return true }
            guard let sourceAccount, let destinationAccount else { return false }
            return storage(of: sourceAccount) == storage(of: destinationAccount)
        }
        if overlaps(source, destination, sameStorage: sameStorage) || overlaps(sourceRoot, destinationRoot) {
            throw BucketeerError.unknown(message: String(
                localized: "sync.error.overlappingEndpoints",
                defaultValue: "The source and the destination of this sync job contain each other. Choose folders that are separate, so the job neither copies into itself nor deletes its own source."
            ))
        }
    }

    /// Where an account's buckets live: the endpoint, plus the storage
    /// account name for providers that put it in the credentials.
    private static func storage(of account: S3Account) -> String {
        S3ClientFactory.endpoint(for: account).absoluteString.lowercased() + "|" + (account.accountID ?? "")
    }

    private static func overlaps(
        _ first: SyncEndpoint,
        _ second: SyncEndpoint,
        sameStorage: (UUID, UUID) -> Bool
    ) -> Bool {
        guard case .s3(let firstAccount, let firstBucket, let firstPrefix) = first,
              case .s3(let secondAccount, let secondBucket, let secondPrefix) = second,
              firstBucket == secondBucket, sameStorage(firstAccount, secondAccount)
        else { return false }
        // A prefix selects every key that starts with it, so `photos`
        // also covers `photos-raw/`.
        return firstPrefix.hasPrefix(secondPrefix) || secondPrefix.hasPrefix(firstPrefix)
    }

    private static func overlaps(_ first: URL?, _ second: URL?) -> Bool {
        guard let first, let second else { return false }
        // Folder names compare the way the volume compares them; the
        // macOS default treats `Photos` and `photos` as one folder.
        let caseSensitive = (try? first.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames ?? false
        // One path is an ancestor of (or equal to) the other when the
        // shorter one is a prefix of the longer.
        return zip(components(of: first), components(of: second)).allSatisfy { a, b in
            caseSensitive ? a == b : a.caseInsensitiveCompare(b) == .orderedSame
        }
    }

    private static func components(of url: URL) -> [String] {
        url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            .map(\.precomposedStringWithCanonicalMapping)
    }
}
