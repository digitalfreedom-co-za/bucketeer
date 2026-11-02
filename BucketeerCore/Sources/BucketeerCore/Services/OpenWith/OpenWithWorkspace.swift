//
//  OpenWithWorkspace.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation
import CryptoKit

/// What an opened file is based on, stored next to it so the file can
/// still be uploaded (or at least identified) after a failed save or a
/// crash.
public struct OpenWithManifest: Codable, Sendable, Equatable {
    public let object: RemoteObjectRef
    /// Name of the local file in its folder (editors may put helper
    /// files next to it).
    public let fileName: String
    /// Unquoted ETag of the server version the file was last equal to.
    public let etag: String?
    /// SHA-256 of the bytes that equal that server version.
    public let digest: Data

    public init(object: RemoteObjectRef, fileName: String, etag: String?, digest: Data) {
        self.object = object
        self.fileName = fileName
        self.etag = etag
        self.digest = digest
    }
}

/// An edit that never reached the server: the local file plus where it
/// belongs. Kept until the user uploads, exports or discards it.
public struct OpenWithRecoveryEntry: Sendable, Equatable, Identifiable {
    public let fileURL: URL
    public let manifest: OpenWithManifest

    public var id: URL { fileURL }
}

/// The folders Open With works in. Every opened file gets its own
/// folder under this launch's session folder (temporary), with its
/// manifest beside it. Files whose edits could not be uploaded move to
/// the recovery folder (Application Support), which survives restarts.
///
/// File operations are best effort: a failure to remove leaves a
/// leftover that the next launch cleans up, and nothing here deletes a
/// file whose contents differ from the server version it is based on.
public struct OpenWithWorkspace: Sendable {
    static let manifestName = ".bucketeer-openwith.json"

    public let workRoot: URL
    public let recoveryRoot: URL
    public let sessionID: String

    public init(workRoot: URL, recoveryRoot: URL, sessionID: String = UUID().uuidString) {
        self.workRoot = workRoot
        self.recoveryRoot = recoveryRoot
        self.sessionID = sessionID
    }

    public var sessionFolder: URL {
        workRoot.appendingPathComponent(sessionID, isDirectory: true)
    }

    /// A fresh, empty folder for one opened file.
    public func makeFileFolder() throws -> URL {
        let folder = sessionFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: - Manifest

    func writeManifest(_ manifest: OpenWithManifest, for fileURL: URL) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL(for: fileURL), options: .atomic)
    }

    func manifest(for fileURL: URL) -> OpenWithManifest? {
        manifest(inFolder: fileURL.deletingLastPathComponent())
    }

    private func manifest(inFolder folder: URL) -> OpenWithManifest? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.manifestName)) else { return nil }
        return try? JSONDecoder().decode(OpenWithManifest.self, from: data)
    }

    private func manifestURL(for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent(Self.manifestName)
    }

    // MARK: - Removing and keeping

    /// Removes the file's folder (only for files the server has).
    func remove(_ fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    /// Moves the file's folder into the recovery folder. `nil` when the
    /// file or its manifest is gone, i.e. there is nothing to keep.
    @discardableResult
    func retain(_ fileURL: URL) -> OpenWithRecoveryEntry? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let manifest = manifest(for: fileURL)
        else {
            remove(fileURL)
            return nil
        }
        let folder = fileURL.deletingLastPathComponent().standardizedFileURL
        if folder.deletingLastPathComponent().path == recoveryRoot.standardizedFileURL.path {
            return OpenWithRecoveryEntry(fileURL: fileURL, manifest: manifest)
        }
        let destination = recoveryRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: recoveryRoot, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: folder, to: destination)
        } catch {
            // Could not move: the file stays where it is, which the
            // next launch's scavenging picks up again.
            return OpenWithRecoveryEntry(fileURL: fileURL, manifest: manifest)
        }
        return OpenWithRecoveryEntry(
            fileURL: destination.appendingPathComponent(fileURL.lastPathComponent),
            manifest: manifest
        )
    }

    public func discard(_ entry: OpenWithRecoveryEntry) {
        remove(entry.fileURL)
    }

    // MARK: - Launch

    /// Folders of earlier launches belong to launches that crashed or
    /// were killed. Files that differ from the server version they are
    /// based on move to recovery; everything else is removed.
    public func scavengeLeftovers() {
        for session in Self.subfolders(of: workRoot) where session.lastPathComponent != sessionID {
            for folder in Self.subfolders(of: session) {
                guard let manifest = manifest(inFolder: folder) else { continue }
                let file = folder.appendingPathComponent(manifest.fileName)
                guard let digest = Self.digest(of: file), digest != manifest.digest else { continue }
                retain(file)
            }
            try? FileManager.default.removeItem(at: session)
        }
    }

    /// Kept edits, oldest first.
    public func recoveries() -> [OpenWithRecoveryEntry] {
        Self.subfolders(of: recoveryRoot)
            .compactMap { folder -> (Date, OpenWithRecoveryEntry)? in
                guard let manifest = manifest(inFolder: folder) else { return nil }
                let file = folder.appendingPathComponent(manifest.fileName)
                guard FileManager.default.fileExists(atPath: file.path) else { return nil }
                let created = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return (created, OpenWithRecoveryEntry(fileURL: file, manifest: manifest))
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    // MARK: - Helpers

    /// Rebuilt from `url` so the paths compare equal to the ones this
    /// type hands out (the directory listing may resolve symlinks such
    /// as /var → /private/var).
    private static func subfolders(of url: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map { url.appendingPathComponent($0.lastPathComponent, isDirectory: true) }
    }

    static func digest(of url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return Data(SHA256.hash(data: data))
    }
}
