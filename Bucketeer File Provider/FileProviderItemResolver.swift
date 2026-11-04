//
//  FileProviderItemResolver.swift
//  Bucketeer File Provider
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import FileProvider
import UniformTypeIdentifiers
import BucketeerCore

/// Concentrates the actual S3/Azure traffic for the File Provider
/// extension. Kept separate from `FileProviderExtension` so the callback
/// shells stay short.
///
/// Identifier layout in v1:
/// - `.rootContainer` → top of the mounted bucket (lists keys under "")
/// - `<encoded-key>`  → either an object or a virtual folder. The key is
///   percent-encoded and base64-folded into the item identifier so the
///   system can round-trip it without colliding with reserved characters.
enum FileProviderItemResolver {

    // MARK: - Identifier encoding

    /// Encode an S3 key as an `NSFileProviderItemIdentifier`.
    static func identifier(for key: String) -> NSFileProviderItemIdentifier {
        if key.isEmpty {
            return .rootContainer
        }
        let encoded = Data(key.utf8).base64EncodedString()
        return NSFileProviderItemIdentifier(encoded)
    }

    /// Reverse the encoding. `.rootContainer` is the empty prefix.
    static func key(from identifier: NSFileProviderItemIdentifier) -> String? {
        if identifier == .rootContainer { return "" }
        guard let data = Data(base64Encoded: identifier.rawValue) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Item

    static func resolve(
        identifier: NSFileProviderItemIdentifier,
        in domain: NSFileProviderDomain,
        container: ExtensionContainer
    ) async throws -> NSFileProviderItem {
        guard let mountInfo = try await container.resolve(domain.identifier.rawValue) else {
            throw mappedError(.providerDomainNotFound)
        }
        if identifier == .rootContainer {
            return ResolvedItem.root(domain: domain)
        }
        guard let key = key(from: identifier) else {
            throw mappedError(.noSuchItem)
        }
        // Synthetic folders (`prefix/`) have no head object to query —
        // S3 / Azure both surface them only as common prefixes during
        // listings. Build a synthetic ResolvedItem for them so Finder
        // can navigate into the folder without round-tripping HEAD.
        if key.hasSuffix("/") {
            return ResolvedItem(
                identifier: identifier,
                parent: parentIdentifier(for: key),
                name: folderName(from: key),
                isFolder: true
            )
        }
        let object: S3Object
        do {
            object = try await container.browser.head(
                account: mountInfo.account,
                bucket: mountInfo.bucket,
                key: key
            )
        } catch {
            throw fileProviderError(error, fallback: .noSuchItem)
        }
        return ResolvedItem(
            identifier: identifier,
            parent: parentIdentifier(for: key),
            object: object
        )
    }

    /// Display name for a synthetic folder prefix (`a/b/c/` → `c`).
    private static func folderName(from key: String) -> String {
        let trimmed = key.hasSuffix("/") ? String(key.dropLast()) : key
        return trimmed.split(separator: "/").last.map(String.init) ?? trimmed
    }

    // MARK: - Fetch

    struct FetchResult {
        let url: URL
        let item: NSFileProviderItem
    }

    /// Downloads the current version, or exactly `requestedVersion`;
    /// the returned item describes the version whose bytes were read.
    static func fetchContents(
        identifier: NSFileProviderItemIdentifier,
        requestedVersion: String?,
        in domain: NSFileProviderDomain,
        container: ExtensionContainer,
        progress: Progress
    ) async throws -> FetchResult {
        guard let mountInfo = try await container.resolve(domain.identifier.rawValue) else {
            throw mappedError(.providerDomainNotFound)
        }
        guard let key = key(from: identifier), !key.isEmpty else {
            throw mappedError(.noSuchItem)
        }
        // Staging file inside the temp dir — the system copies it into
        // the user's container on success and discards the original.
        let staging = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let object: S3Object
        do {
            object = try await mounted(mountInfo, container: container, progress: progress).fetch(
                key,
                requestedVersion: requestedVersion,
                to: staging
            )
        } catch MountedBucket.Refusal.versionUnavailable {
            try? FileManager.default.removeItem(at: staging)
            throw mappedError(.versionNoLongerAvailable)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw fileProviderError(error, fallback: .serverUnreachable)
        }
        let item = ResolvedItem(
            identifier: identifier,
            parent: parentIdentifier(for: key),
            object: object
        )
        return FetchResult(url: staging, item: item)
    }

    // MARK: - Create

    /// Files are created only if the name is free. A taken name keeps
    /// its object: the new file goes up as a conflict copy (and Finder
    /// shows it under that name), unless `mayAlreadyExist` (re-import)
    /// finds the identical object already there.
    static func createItem(
        template: NSFileProviderItem,
        contents: URL?,
        options: NSFileProviderCreateItemOptions,
        in domain: NSFileProviderDomain,
        container: ExtensionContainer,
        progress: Progress
    ) async throws -> NSFileProviderItem {
        guard let mountInfo = try await container.resolve(domain.identifier.rawValue) else {
            throw mappedError(.providerDomainNotFound)
        }
        // Unknown parents (trash, working set) must not fall back to the
        // bucket root.
        guard let parentKey = key(from: template.parentItemIdentifier) else {
            throw mappedError(.noSuchItem)
        }
        let isFolder = template.contentType == .folder
        // Folders carry the trailing slash so the identifier round-trips
        // through `resolve` without needing a HEAD lookup. Files use the
        // plain `parentKey + filename`.
        let key: String
        if isFolder {
            let raw = parentKey + template.filename
            key = raw.hasSuffix("/") ? raw : raw + "/"
        } else {
            key = parentKey + template.filename
        }
        if !isFolder, let contents {
            do {
                let placement = try await mounted(mountInfo, container: container, progress: progress).create(
                    key, contents: contents, mayAlreadyExist: options.contains(.mayAlreadyExist)
                )
                if placement.isConflict {
                    await announceConflict(.conflictCopy, key: key, in: domain)
                }
                return ResolvedItem(
                    identifier: identifier(for: placement.object.key),
                    parent: template.parentItemIdentifier,
                    object: placement.object
                )
            } catch {
                throw fileProviderError(error, fallback: .cannotSynchronize)
            }
        }
        if isFolder {
            // An existing folder of that name is merged into, which
            // replaces nothing.
            do {
                try await container.browser.createFolder(
                    account: mountInfo.account,
                    bucket: mountInfo.bucket,
                    prefix: key
                )
            } catch {
                throw fileProviderError(error, fallback: .cannotSynchronize)
            }
            // Synthesised — there is no head object for a folder marker
            // on S3 (and not always on Azure either).
            return ResolvedItem(
                identifier: identifier(for: key),
                parent: template.parentItemIdentifier,
                name: folderName(from: key),
                isFolder: true
            )
        }
        // A file without contents: report whatever the server holds.
        // The HEAD crosses the network too — it must produce an
        // NSFileProviderError like everything else.
        let head: S3Object
        do {
            head = try await container.browser.head(
                account: mountInfo.account,
                bucket: mountInfo.bucket,
                key: key
            )
        } catch {
            throw fileProviderError(error, fallback: .cannotSynchronize)
        }
        return ResolvedItem(
            identifier: identifier(for: key),
            parent: template.parentItemIdentifier,
            object: head
        )
    }

    // MARK: - Modify

    struct ModifyResult {
        let item: NSFileProviderItem
        /// True when the server kept its own version and the system must
        /// download it again (the local edit went into a conflict copy).
        let shouldFetchContent: Bool
    }

    static func modifyItem(
        item: NSFileProviderItem,
        baseVersion: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents: URL?,
        in domain: NSFileProviderDomain,
        container: ExtensionContainer,
        progress: Progress
    ) async throws -> ModifyResult {
        guard let mountInfo = try await container.resolve(domain.identifier.rawValue) else {
            throw mappedError(.providerDomainNotFound)
        }
        guard let originalKey = key(from: item.itemIdentifier) else {
            throw mappedError(.noSuchItem)
        }
        // Belt-and-braces behind the capabilities gate: renaming a
        // folder prefix would need a recursive copy+delete of every
        // descendant — moving only the marker orphans the children.
        if originalKey.hasSuffix("/"),
           changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier) {
            throw mappedError(.cannotSynchronize)
        }
        let isMove = changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier)
        var currentKey = originalKey
        var written: Written?
        // Every network call below must surface as an
        // NSFileProviderError — createItem/deleteItem already wrap;
        // an unmapped BucketeerError here would land in a foreign
        // error domain and confuse the system's retry logic.
        do {
            // Contents first, against the key the edit was based on.
            if changedFields.contains(.contents), let contents {
                written = try await uploadIfUnchanged(
                    contents,
                    key: originalKey,
                    baseVersion: baseVersion,
                    mountInfo: mountInfo,
                    container: container,
                    progress: progress
                )
                if written == nil {
                    return try await keepServerVersion(
                        of: originalKey,
                        conflictCopyOf: isMove ? try moveTarget(of: item) : originalKey,
                        contents: contents,
                        in: domain,
                        mountInfo: mountInfo,
                        container: container,
                        progress: progress
                    )
                }
            }
            // Rename = conditional server-side copy + conditional delete,
            // against the version this change is based on (the one just
            // written, or Finder's base version).
            if isMove {
                let newKey = try moveTarget(of: item)
                if newKey != originalKey {
                    let placement = try await mounted(mountInfo, container: container, progress: progress).rename(
                        originalKey,
                        baseVersion: written?.etag ?? String(data: baseVersion.contentVersion, encoding: .utf8),
                        to: newKey
                    )
                    if placement.isConflict {
                        let kind: ConflictNotice.Kind = placement.object.key == originalKey
                            ? .renameKeptServerVersion : .conflictCopy
                        await announceConflict(kind, key: newKey, in: domain)
                    }
                    currentKey = placement.object.key
                }
            }
            // The HEAD supplies the metadata only. If it already shows
            // a version other than the one our write answered with,
            // somebody wrote after us: the local contents are not that
            // version, so the system has to fetch it.
            let head = try await container.browser.head(
                account: mountInfo.account,
                bucket: mountInfo.bucket,
                key: currentKey
            )
            let newerOnServer = written.map { !ETag.matches(base: $0.etag, current: head.etag) } ?? false
            return ModifyResult(
                item: ResolvedItem(
                    identifier: identifier(for: currentKey),
                    parent: parentIdentifier(for: currentKey),
                    object: head
                ),
                shouldFetchContent: newerOnServer
            )
        } catch {
            throw fileProviderError(error, fallback: .cannotSynchronize)
        }
    }

    private static func moveTarget(of item: NSFileProviderItem) throws -> String {
        guard let parentKey = key(from: item.parentItemIdentifier) else {
            throw mappedError(.noSuchItem)
        }
        return parentKey + item.filename
    }

    /// A content write the server accepted; `etag` is what the write
    /// answered with.
    private struct Written {
        let etag: String?
    }

    /// Uploads only while the server still has the version Finder's
    /// edit was based on: a HEAD compare first (also catches providers
    /// that ignore If-Match), then the write itself with If-Match.
    /// Returns `nil` when the server version differs or is gone.
    private static func uploadIfUnchanged(
        _ contents: URL,
        key: String,
        baseVersion: NSFileProviderItemVersion,
        mountInfo: (account: S3Account, bucket: String),
        container: ExtensionContainer,
        progress: Progress
    ) async throws -> Written? {
        let base = String(data: baseVersion.contentVersion, encoding: .utf8)
        let serverETag = try await currentETag(of: key, mountInfo: mountInfo, container: container)
        guard ETag.matches(base: base, current: serverETag), let base else { return nil }
        do {
            return Written(etag: try await uploadFile(
                contents,
                account: mountInfo.account,
                bucket: mountInfo.bucket,
                key: key,
                precondition: .ifMatch(base),
                container: container,
                progress: progress
            ))
        } catch BucketeerError.preconditionFailed {
            return nil
        }
    }

    /// Conflict: the edit goes up as `<name> (conflict <date> <tag>).<ext>`,
    /// created only if that name is free (never replacing another
    /// copy), the item keeps the server's version (Finder downloads it
    /// again) and the working set is signalled so the copy shows up.
    /// When the server object was deleted, the item is reported as gone.
    private static func keepServerVersion(
        of key: String,
        conflictCopyOf targetKey: String,
        contents: URL,
        in domain: NSFileProviderDomain,
        mountInfo: (account: S3Account, bucket: String),
        container: ExtensionContainer,
        progress: Progress
    ) async throws -> ModifyResult {
        _ = try await ConflictCopyName.create(copyOf: targetKey, date: Date()) { copyKey -> Bool? in
            do {
                try await uploadFile(
                    contents,
                    account: mountInfo.account,
                    bucket: mountInfo.bucket,
                    key: copyKey,
                    precondition: .ifAbsent,
                    container: container,
                    progress: progress
                )
                return true
            } catch BucketeerError.preconditionFailed {
                return nil
            }
        }
        await announceConflict(.conflictCopy, key: targetKey, in: domain)
        guard let head = try await currentHead(of: key, mountInfo: mountInfo, container: container) else {
            throw mappedError(.noSuchItem)
        }
        return ModifyResult(
            item: ResolvedItem(identifier: identifier(for: key), parent: parentIdentifier(for: key), object: head),
            shouldFetchContent: true
        )
    }

    private static func currentETag(
        of key: String,
        mountInfo: (account: S3Account, bucket: String),
        container: ExtensionContainer
    ) async throws -> String? {
        try await currentHead(of: key, mountInfo: mountInfo, container: container)?.etag
    }

    private static func currentHead(
        of key: String,
        mountInfo: (account: S3Account, bucket: String),
        container: ExtensionContainer
    ) async throws -> S3Object? {
        do {
            return try await container.browser.head(account: mountInfo.account, bucket: mountInfo.bucket, key: key)
        } catch BucketeerError.objectNotFound {
            return nil
        }
    }

    // MARK: - Delete

    /// Files are deleted only while the server still has `baseVersion`;
    /// a newer version is kept and the deletion rejected, so Finder
    /// brings the item back.
    static func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion: NSFileProviderItemVersion,
        in domain: NSFileProviderDomain,
        container: ExtensionContainer
    ) async throws {
        guard let mountInfo = try await container.resolve(domain.identifier.rawValue) else {
            throw mappedError(.providerDomainNotFound)
        }
        guard let key = key(from: identifier), !key.isEmpty else {
            throw mappedError(.noSuchItem)
        }
        let bucket = mounted(mountInfo, container: container, progress: Progress())
        do {
            if key.hasSuffix("/") {
                // A folder is a prefix: deleting only its marker would
                // orphan every descendant while Finder reports success.
                try await bucket.deleteFolder(key)
            } else {
                try await bucket.delete(key, baseVersion: String(data: baseVersion.contentVersion, encoding: .utf8))
            }
        } catch MountedBucket.Refusal.changedOnServer where key.hasSuffix("/") {
            await announceConflict(.deletionRefused, key: key, in: domain)
            throw NSError.fileProviderErrorForRejectedDeletion(
                of: ResolvedItem(
                    identifier: identifier,
                    parent: parentIdentifier(for: key),
                    object: S3Object(key: key, size: 0, lastModified: Date(), etag: "", isFolder: true)
                )
            )
        } catch MountedBucket.Refusal.changedOnServer {
            let current: S3Object?
            do {
                current = try await currentHead(of: key, mountInfo: mountInfo, container: container)
            } catch {
                // The newer object is still there; the delete must not
                // be reported as done just because the HEAD failed.
                throw fileProviderError(error, fallback: .cannotSynchronize)
            }
            // Deleted by someone else meanwhile: nothing left to keep.
            guard let current else { return }
            await announceConflict(.deletionRefused, key: key, in: domain)
            throw NSError.fileProviderErrorForRejectedDeletion(
                of: ResolvedItem(identifier: identifier, parent: parentIdentifier(for: key), object: current)
            )
        } catch {
            throw fileProviderError(error, fallback: .cannotSynchronize)
        }
    }

    // MARK: - Version rules

    private static func mounted(
        _ mountInfo: (account: S3Account, bucket: String),
        container: ExtensionContainer,
        progress: Progress
    ) -> MountedBucket {
        MountedBucket(
            browser: container.browser,
            account: mountInfo.account,
            bucket: mountInfo.bucket,
            transport: ExtensionTransport(account: mountInfo.account, bucket: mountInfo.bucket,
                                          container: container, progress: progress)
        )
    }

    /// The server object differed from what Finder expected and both
    /// versions were kept: show the change in Finder and tell the user.
    private static func announceConflict(_ kind: ConflictNotice.Kind, key: String, in domain: NSFileProviderDomain) async {
        try? await NSFileProviderManager(for: domain)?.signalEnumerator(for: .workingSet)
        ConflictNotice.post(kind, fileName: displayName(of: key))
    }

    private static func displayName(of key: String) -> String {
        key.split(separator: "/").last.map(String.init) ?? key
    }

    // MARK: - Transports

    /// Direct transfers that bypass the host's TransferManager queue:
    /// S3 multipart via Soto, Azure via the ranged-parallel transporter.
    private struct ExtensionTransport: MountedContentTransport {
        let account: S3Account
        let bucket: String
        let container: ExtensionContainer
        let progress: Progress

        func upload(_ url: URL, to key: String, precondition: WritePrecondition?) async throws -> String? {
            try await FileProviderItemResolver.uploadFile(
                url, account: account, bucket: bucket, key: key,
                precondition: precondition, container: container, progress: progress
            )
        }

        func download(_ key: String, matching etag: String, size: Int64, to url: URL) async throws {
            switch account.provider.family {
            case .azureBlob:
                try await container.azureTransporter.download(
                    account: account,
                    container: bucket,
                    blob: key,
                    localURL: url,
                    ifMatch: etag,
                    progress: { [progress] bytes, total in
                        FileProviderItemResolver.publish(progress: progress, bytes: bytes, total: total)
                    }
                )
            case .s3:
                try await S3DirectFetch.download(
                    account: account,
                    bucket: bucket,
                    key: key,
                    etag: etag,
                    size: size,
                    to: url,
                    factory: container.clientFactory
                )
                FileProviderItemResolver.publish(progress: progress, bytes: size, total: size)
            }
        }
    }

    /// Returns the ETag the write answered with.
    @discardableResult
    private static func uploadFile(
        _ url: URL,
        account: S3Account,
        bucket: String,
        key: String,
        precondition: WritePrecondition? = nil,
        container: ExtensionContainer,
        progress: Progress
    ) async throws -> String? {
        switch account.provider.family {
        case .azureBlob:
            return try await container.azureTransporter.upload(
                account: account,
                container: bucket,
                blob: key,
                localURL: url,
                contentType: contentType(for: url),
                precondition: precondition,
                progress: { bytes, total in
                    Self.publish(progress: progress, bytes: bytes, total: total)
                }
            )
        case .s3:
            let etag = try await S3DirectFetch.upload(
                account: account,
                bucket: bucket,
                key: key,
                localURL: url,
                contentType: contentType(for: url),
                precondition: precondition,
                factory: container.clientFactory
            )
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            Self.publish(progress: progress, bytes: Int64(size), total: Int64(size))
            return etag
        }
    }

    private static func publish(progress: Progress, bytes: Int64, total: Int64) {
        guard total > 0 else { return }
        progress.totalUnitCount = total
        progress.completedUnitCount = bytes
    }

    private static func contentType(for url: URL) -> String? {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
    }

    // MARK: - Helpers

    static func parentIdentifier(for key: String) -> NSFileProviderItemIdentifier {
        let trimmed = key.hasSuffix("/") ? String(key.dropLast()) : key
        guard let lastSlash = trimmed.lastIndex(of: "/") else {
            return .rootContainer
        }
        let parentPrefix = String(trimmed[..<trimmed.index(after: lastSlash)])
        return identifier(for: parentPrefix)
    }

    static func fileProviderError(_ error: Error, fallback: NSFileProviderError.Code) -> Error {
        let nsError = error as NSError
        if nsError.domain == NSFileProviderErrorDomain {
            return nsError
        }
        if let bucketeer = error as? BucketeerError {
            switch bucketeer {
            case .objectNotFound, .bucketNotFound:
                return mappedError(.noSuchItem)
            case .authenticationFailed:
                return mappedError(.notAuthenticated)
            case .networkUnavailable:
                return mappedError(.serverUnreachable)
            default:
                return mappedError(fallback)
            }
        }
        return mappedError(fallback)
    }

    static func mappedError(_ code: NSFileProviderError.Code) -> Error {
        NSError(
            domain: NSFileProviderErrorDomain,
            code: code.rawValue,
            userInfo: [:]
        )
    }
}

/// Concrete `NSFileProviderItem` for browsed objects. Folders surface
/// the `.folder` UTType so Finder treats them like real directories.
final class ResolvedItem: NSObject, NSFileProviderItem {
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let isFolder: Bool
    let size: Int64
    let modificationDate: Date?
    let etag: String

    init(
        identifier: NSFileProviderItemIdentifier,
        parent: NSFileProviderItemIdentifier,
        object: S3Object
    ) {
        self.itemIdentifier = identifier
        self.parentItemIdentifier = parent
        self.filename = object.displayName
        self.isFolder = object.isFolder
        self.size = object.size
        // Folders are listing prefixes without a date (`.distantPast`);
        // Finder would show year 1.
        self.modificationDate = object.lastModified == .distantPast ? nil : object.lastModified
        self.etag = object.etag
        super.init()
    }

    init(
        identifier: NSFileProviderItemIdentifier,
        parent: NSFileProviderItemIdentifier,
        name: String,
        isFolder: Bool
    ) {
        self.itemIdentifier = identifier
        self.parentItemIdentifier = parent
        self.filename = name
        self.isFolder = isFolder
        self.size = 0
        self.modificationDate = nil
        self.etag = ""
        super.init()
    }

    static func root(domain: NSFileProviderDomain) -> ResolvedItem {
        ResolvedItem(
            identifier: .rootContainer,
            parent: .rootContainer,
            name: domain.displayName,
            isFolder: true
        )
    }

    var documentSize: NSNumber? {
        isFolder ? nil : NSNumber(value: size)
    }

    var capabilities: NSFileProviderItemCapabilities {
        // The root container (the bucket itself) cannot be renamed or
        // deleted via Finder — that would require a `DeleteBucket`
        // call we do not expose. Returning the
        // folder capabilities here let Finder offer a Delete that
        // would silently fail.
        if itemIdentifier == .rootContainer {
            return [.allowsContentEnumerating, .allowsAddingSubItems]
        }
        if isFolder {
            // No .allowsRenaming: a folder is a virtual prefix — a
            // rename would have to copy+delete every descendant.
            // v1 doesn't implement that, and offering the action just
            // to fail (or worse, move only the marker and orphan the
            // children) is the worst outcome.
            return [.allowsContentEnumerating, .allowsAddingSubItems, .allowsDeleting]
        }
        return [.allowsReading, .allowsWriting, .allowsDeleting, .allowsRenaming]
    }

    var contentType: UTType {
        isFolder ? .folder : (UTType(filenameExtension: (filename as NSString).pathExtension) ?? .data)
    }

    var itemVersion: NSFileProviderItemVersion {
        // ETag drives the content version so the system re-fetches on
        // server-side changes. Metadata version cycles with the same
        // string for now — Phase 9.5.1 may split them once we track
        // server-side LastModified independently.
        let versionData = Data(etag.utf8)
        return NSFileProviderItemVersion(
            contentVersion: versionData,
            metadataVersion: versionData
        )
    }
}
