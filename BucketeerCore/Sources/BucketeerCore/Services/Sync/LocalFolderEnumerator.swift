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
    /// to move it into place. Atomic — see `place` — so a failed move
    /// never leaves the destination in an inconsistent state.
    /// Path-traversal guarded via `safeChildURL` so a malicious S3 key
    /// cannot escape the chosen sync root.
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
        try place(temp, at: destination)
    }

    /// Moves a staged file to `destination`, replacing a file there
    /// atomically and never a folder.
    ///
    /// The file first moves beside the destination (a copy when it is
    /// staged on another volume), so the last step is one `rename(2)`
    /// in the same folder. A folder at the destination makes that step
    /// itself fail, so one created after any earlier look survives too.
    /// `replaceItemAt` would delete it with its contents, and the folder
    /// walk skips hidden files, so a folder holding only those looks
    /// empty to the planner.
    ///
    /// A replaced file keeps its permissions, so a `0600` file does not
    /// become readable for others and a script stays executable.
    public static func place(_ staged: URL, at destination: URL) throws {
        let incoming = destination.deletingLastPathComponent()
            .appendingPathComponent(".bucketeer-placing-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: staged, to: incoming)
            try adoptPermissions(of: destination, to: incoming)
            try replace(destination, with: incoming)
        } catch {
            // Only ever the staged file or a partial copy of it; `unlink`
            // never removes a folder.
            unlink(incoming.path)
            throw error
        }
    }

    /// Gives `incoming` the permission bits of the file at `destination`;
    /// nothing to adopt when no file is there.
    private static func adoptPermissions(of destination: URL, to incoming: URL) throws {
        var existing = stat()
        guard lstat(destination.path, &existing) == 0, existing.st_mode & S_IFMT == S_IFREG else { return }
        guard chmod(incoming.path, existing.st_mode & 0o777) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// The replacing step: `rename(2)` swaps a file in one step and
    /// refuses a folder with `EISDIR`, on APFS, HFS+, exFAT and FAT alike.
    static func replace(_ destination: URL, with incoming: URL) throws {
        guard rename(incoming.path, destination.path) != 0 else { return }
        let code = errno
        guard code != EISDIR else {
            throw BucketeerError.providerError(
                statusCode: 409,
                message: "A folder named \(destination.lastPathComponent) already exists in the destination, so the file was not written over it."
            )
        }
        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }

    /// Removes the file only while it still has `fingerprint`, i.e. was
    /// not saved again since it was listed. Returns `false` and keeps
    /// the file when it changed or a folder took its name; `true` when
    /// removed or already gone. Path-traversal guarded so a hostile
    /// relative key cannot reach outside `root`.
    ///
    /// The file is never unlinked: `discard` sets it aside (the Trash by
    /// default) and returns where it went. An editor that still has the
    /// file open keeps writing into that copy, so no ordering of its
    /// writes against this call loses data. A coordinated move lets
    /// document-based apps save first and follow the file. When it
    /// cannot be set aside, the file stays and the error is thrown.
    public static func deleteIfUnchanged(
        relativeKey: String,
        under root: URL,
        fingerprint: LocalFileFingerprint,
        discard: (URL) throws -> URL? = moveToTrash
    ) throws -> Bool {
        let target = try safeChildURL(root: root, relativeKey: relativeKey)
        guard FileManager.default.fileExists(atPath: target.path) else { return true }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var outcome: Result<Bool, Error> = .success(false)
        coordinator.coordinate(writingItemAt: target, options: .forMoving, error: &coordinationError) { url in
            outcome = Result {
                switch try setAsideIfUnchanged(url, fingerprint: fingerprint, discard: discard) {
                case .changed:
                    return false
                case .removed(let location):
                    if let location { coordinator.item(at: url, didMoveTo: location) }
                    return true
                }
            }
        }
        if let coordinationError { throw coordinationError }
        return try outcome.get()
    }

    /// The user's Trash on the file's volume; throws where there is none.
    public static func moveToTrash(_ url: URL) throws -> URL? {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }

    private enum SetAside {
        /// The file changed and was put back.
        case changed
        /// Set aside at the location, if known (`nil` when it was already
        /// gone or `discard` did not say).
        case removed(URL?)
    }

    private static func setAsideIfUnchanged(
        _ target: URL,
        fingerprint: LocalFileFingerprint,
        discard: (URL) throws -> URL?
    ) throws -> SetAside {
        // Take the file out of reach first (a rename is atomic), then
        // check the file that was actually taken: a save that replaced
        // it between check and removal can no longer be the one removed.
        // It keeps its name inside a hidden holder, so the Trash shows it
        // as the user knows it.
        let holder = target.deletingLastPathComponent()
            .appendingPathComponent(".bucketeer-deleting-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: holder, withIntermediateDirectories: false)
        // rmdir removes the holder only once it is empty.
        defer { rmdir(holder.path) }
        let claimed = holder.appendingPathComponent(target.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: target, to: claimed)
        } catch where !FileManager.default.fileExists(atPath: target.path) {
            return .removed(nil)
        }
        let unchanged: Bool
        var location: URL?
        do {
            // A folder has no size, so its date alone could match: only a
            // regular file can be the one that was listed.
            let values = try claimed.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            unchanged = values.isRegularFile == true && LocalFileFingerprint(
                size: Int64(values.fileSize ?? 0),
                modified: values.contentModificationDate ?? .distantPast
            ) == fingerprint
            if unchanged { location = try discard(claimed) }
        } catch {
            // The holder is hidden from every listing; whatever is left
            // of the item has to go back where the user had it.
            try? restore(claimed, to: target)
            throw error
        }
        guard unchanged else {
            try restore(claimed, to: target)
            return .changed
        }
        return .removed(location)
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
