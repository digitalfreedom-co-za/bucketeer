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
    /// around this call.
    public static func enumerate(at root: URL) throws -> [S3Object] {
        var results: [S3Object] = []
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .producesRelativePathURLs]
        ) else {
            return []
        }
        for case let url as URL in walker {
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
        return results
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
/// when the destination is `.localFolder` — copies a downloaded
/// payload into the right relative path inside the folder root,
/// creating any missing parent directories.
public enum LocalFolderWriter {

    /// Write `data` to `<root>/<relativeKey>`, creating parent
    /// directories as needed. Atomic-on-success: writes to a temp
    /// path then renames so a partial write never replaces the final
    /// file. Caller holds security-scoped access to `root`.
    public static func write(
        _ data: Data,
        relativeKey: String,
        under root: URL
    ) throws {
        let destination = root.appending(path: relativeKey)
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
    }

    /// Copy an already-downloaded file to the target relative path.
    /// Useful when a downstream component (e.g. `S3DirectFetch`)
    /// produced the file in a staging location and we just need to
    /// move it into place.
    public static func install(
        from temp: URL,
        relativeKey: String,
        under root: URL
    ) throws {
        let destination = root.appending(path: relativeKey)
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        // Replace any existing file atomically.
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    /// Delete a local file under the folder root. Idempotent — missing
    /// files are silently OK because the sync engine may compute a
    /// delete plan against a moved-since-then folder.
    public static func delete(relativeKey: String, under root: URL) throws {
        let target = root.appending(path: relativeKey)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }
}
