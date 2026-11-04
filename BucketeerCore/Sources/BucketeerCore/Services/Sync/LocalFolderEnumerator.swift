//
//  LocalFolderEnumerator.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation

/// Walks a local folder recursively and yields one `S3Object` per
/// regular file, with the key set to the path relative to the folder
/// root (e.g. `subdir/photo.jpg`). Folders are skipped from the result
/// — they're recreated implicitly by `LocalFolderWriter` when files
/// land inside them.
///
/// Reuses the `S3Object` value type so the planner can diff a local
/// folder against an S3 prefix using exactly the same data structure.
/// Local files have an empty `etag` because there is no provider-side
/// fingerprint for them; the planner's `nameAndSize` strategy is the
/// only viable one for cross-system diffs.
public enum LocalFolderEnumerator {

    /// Recursively enumerate every regular file under `root`. Caller is
    /// responsible for security-scoped resource access (start/stop)
    /// around this call. Periodically checks
    /// `Task.checkCancellation()` so a user-initiated sync cancel
    /// during a large folder walk actually stops promptly instead of
    /// running to completion and only honouring the cancel afterwards.
    public static func enumerate(at root: URL) throws -> [S3Object] {
        var results: [S3Object] = []
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        // A missing, unmounted or unreadable folder must fail the run,
        // not enumerate as empty: the planner would otherwise schedule a
        // mirror delete for every destination key.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw unavailableError }
        var walkFailed = false
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .producesRelativePathURLs],
            errorHandler: { _, _ in
                walkFailed = true
                return false
            }
        ) else {
            throw unavailableError
        }
        var counter = 0
        for case let url as URL in walker {
            counter += 1
            // Check cancellation every 256 entries to keep the
            // overhead negligible while still surfacing cancels within
            // a few milliseconds on a fast SSD.
            if counter % 256 == 0 {
                try Task.checkCancellation()
            }
            let values = try url.resourceValues(forKeys: keys)
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { continue }
            // `producesRelativePathURLs` gives us URLs whose
            // `.relativePath` is the path beneath `root` (e.g.
            // `subdir/photo.jpg`). Normalise to forward slashes
            // explicitly so the diff against S3 keys matches even on
            // case-preserving HFS+ volumes.
            let relative = url.relativePath
            results.append(S3Object(
                key: relative,
                size: Int64(values.fileSize ?? 0),
                lastModified: values.contentModificationDate ?? .distantPast,
                etag: "",
                isFolder: false
            ))
        }
        if walkFailed { throw unavailableError }
        return results
    }

    private static var unavailableError: BucketeerError {
        .unknown(message: String(
            localized: "sync.error.localFolderUnavailable",
            defaultValue: "The local folder is missing or could not be read completely, so the sync job stopped before changing anything."
        ))
    }

    /// Resolve a security-scoped bookmark back to a URL. Caller must
    /// `startAccessingSecurityScopedResource()` before reading from
    /// the returned URL and `stopAccessingSecurityScopedResource()`
    /// when done. Returns `(url, isStale)` so the caller can re-create
    /// the bookmark when macOS reports the underlying file moved.
    public static func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }
}

/// Writer / deleter for the local-folder side. Used by `SyncEngine`
/// when the destination is `.localFolder` — installs a downloaded
/// payload into the right relative path inside the folder root,
/// creating any missing parent directories.
public enum LocalFolderWriter {

    /// Copy an already-downloaded file to the target relative path.
    /// Used by `SyncEngine` when the source has produced a staging
    /// file (e.g. from the TransferManager download path) and we need
    /// to move it into place. Atomic — uses
    /// `replaceItemAt` so a failed move never leaves the destination
    /// in an inconsistent state. Path-traversal guarded via
    /// `safeChildURL` so a malicious S3 key cannot escape the chosen
    /// sync root.
    public static func install(
        from temp: URL,
        relativeKey: String,
        under root: URL
    ) throws {
        let destination = try safeChildURL(root: root, relativeKey: relativeKey)
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        // `replaceItemAt` is atomic on the same volume and preserves
        // the original file until the new one is fully present. If
        // the destination doesn't yet exist, fall back to `moveItem`
        // which is also atomic on the same volume.
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(
                destination,
                withItemAt: temp,
                backupItemName: nil,
                options: []
            )
        } else {
            try FileManager.default.moveItem(at: temp, to: destination)
        }
    }

    /// Delete a local file under the folder root. Idempotent — missing
    /// files are silently OK because the sync engine may compute a
    /// delete plan against a moved-since-then folder. Path-traversal
    /// guarded so a mirror-delete plan with a hostile relative key
    /// can't reach outside the chosen root.
    public static func delete(relativeKey: String, under root: URL) throws {
        let target = try safeChildURL(root: root, relativeKey: relativeKey)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }

    /// Deletes the file only while it still has `fingerprint`, i.e. was
    /// not saved again since it was listed. Returns `false` and keeps
    /// the file when it changed; `true` when deleted or already gone.
    public static func deleteIfUnchanged(
        relativeKey: String,
        under root: URL,
        fingerprint: LocalFileFingerprint
    ) throws -> Bool {
        let target = try safeChildURL(root: root, relativeKey: relativeKey)
        guard FileManager.default.fileExists(atPath: target.path) else { return true }
        // Take the file out of reach first (a rename is atomic), then
        // check the file that was actually taken: a save that replaced
        // it between check and delete can no longer be the one deleted.
        let claimed = target.deletingLastPathComponent()
            .appendingPathComponent(".bucketeer-deleting-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: target, to: claimed)
        } catch where !FileManager.default.fileExists(atPath: target.path) {
            return true
        }
        let values = try claimed.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let current = LocalFileFingerprint(
            size: Int64(values.fileSize ?? 0),
            modified: values.contentModificationDate ?? .distantPast
        )
        if current == fingerprint {
            try FileManager.default.removeItem(at: claimed)
            return true
        }
        try restore(claimed, to: target)
        return false
    }

    /// Symlinks resolved in the part of the path that exists; the
    /// missing tail (a file about to be written) is appended unchanged.
    private static func resolvedPath(of url: URL) -> String {
        var existing = url
        var tail: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.pathComponents.count > 1 {
            tail.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        return ([existing.resolvingSymlinksInPath().path] + tail).joined(separator: "/")
    }

    /// Puts a changed file back; if its name was taken meanwhile, it
    /// becomes a conflict copy beside it instead of replacing anything.
    private static func restore(_ claimed: URL, to target: URL) throws {
        do {
            try FileManager.default.moveItem(at: claimed, to: target)
        } catch {
            let name = ConflictCopyName.key(for: target.lastPathComponent, date: Date(), tag: ConflictCopyName.randomTag())
            try FileManager.default.moveItem(at: claimed, to: target.deletingLastPathComponent().appendingPathComponent(name))
        }
    }

    /// Confine every write/delete to paths whose
    /// resolved form lives inside `root`. Rejects absolute paths,
    /// `.`/`..` components, and the empty string. Both `root` and the
    /// resolved destination are `standardized` (symlinks resolved,
    /// `..` normalised) so a key like `subdir/../../../etc/passwd`
    /// cannot land outside the chosen folder.
    ///
    /// The key is used byte for byte: ` report.txt` stays a different
    /// file from `report.txt`. Empty or blank components (`a//b`,
    /// `a/`) are rejected, because the file system would collapse them
    /// onto another key.
    public static func safeChildURL(
        root: URL,
        relativeKey: String
    ) throws -> URL {
        guard !relativeKey.isEmpty else {
            throw BucketeerError.providerError(
                statusCode: 400,
                message: "Empty relative key — refusing to operate on the folder root itself."
            )
        }
        // Reject absolute paths outright.
        if relativeKey.hasPrefix("/") || relativeKey.hasPrefix("\\") {
            throw BucketeerError.providerError(
                statusCode: 400,
                message: "Relative key resolves to an absolute path: \(relativeKey)"
            )
        }
        // Reject any path component that's `.` or `..` — even one
        // such component anywhere in the path means the key tries to
        // climb out.
        let components = relativeKey.split(separator: "/", omittingEmptySubsequences: false)
        for component in components where component == ".." || component == "." {
            throw BucketeerError.providerError(
                statusCode: 400,
                message: "Relative key contains a path-traversal component: \(relativeKey)"
            )
        }
        if components.contains(where: { $0.allSatisfy(\.isWhitespace) }) {
            throw BucketeerError.providerError(
                statusCode: 400,
                message: "Relative key contains an empty path component: \(relativeKey)"
            )
        }
        let candidate = root.appending(path: relativeKey).standardizedFileURL
        let rootStandard = root.standardizedFileURL
        guard candidate.path.hasPrefix(rootStandard.path + "/") || candidate.path == rootStandard.path else {
            throw BucketeerError.providerError(
                statusCode: 400,
                message: "Relative key escapes the sync root: \(relativeKey)"
            )
        }
        // A symlink inside the root would let two keys (or a key and a
        // path outside the root) reach the same file.
        // Compared without case and normalisation, which the file system
        // may report in its own spelling.
        let expected = (resolvedPath(of: rootStandard) + "/" + relativeKey).precomposedStringWithCanonicalMapping
        let resolved = resolvedPath(of: candidate).precomposedStringWithCanonicalMapping
        guard resolved.caseInsensitiveCompare(expected) == .orderedSame else {
            throw BucketeerError.providerError(
                statusCode: 400,
                message: "Relative key passes through a symbolic link: \(relativeKey)"
            )
        }
        return candidate
    }
}
