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

    static func fetchContents(
        identifier: NSFileProviderItemIdentifier,
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
            object = try await container.browser.head(
                account: mountInfo.account,
                bucket: mountInfo.bucket,
                key: key
            )
            try await downloadObject(
                account: mountInfo.account,
                bucket: mountInfo.bucket,
                key: key,
                size: object.size,
                to: staging,
                container: container,
                progress: progress
            )
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

    static func createItem(
        template: NSFileProviderItem,
        contents: URL?,
        in domain: NSFileProviderDomain,
        container: ExtensionContainer,
        progress: Progress
    ) async throws -> NSFileProviderItem {
        guard let mountInfo = try await container.resolve(domain.identifier.rawValue) else {
            throw mappedError(.providerDomainNotFound)
        }
        let parentKey = key(from: template.parentItemIdentifier) ?? ""
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
        do {
            if isFolder {
                try await container.browser.createFolder(
                    account: mountInfo.account,
                    bucket: mountInfo.bucket,
                    prefix: key
                )
            } else if let contents {
                try await uploadFile(
                    contents,
                    account: mountInfo.account,
                    bucket: mountInfo.bucket,
                    key: key,
                    container: container,
                    progress: progress
                )
            }
        } catch {
            throw fileProviderError(error, fallback: .cannotSynchronize)
        }
        if isFolder {
            // Synthesised — there is no head object for a folder marker
            // on S3 (and not always on Azure either).
            return ResolvedItem(
                identifier: identifier(for: key),
                parent: template.parentItemIdentifier,
                name: folderName(from: key),
                isFolder: true
            )
        }
        let head = try await container.browser.head(
            account: mountInfo.account,
            bucket: mountInfo.bucket,
            key: key
        )
        return ResolvedItem(
            identifier: identifier(for: key),
            parent: template.parentItemIdentifier,
            object: head
        )
    }

    // MARK: - Modify

    static func modifyItem(
        item: NSFileProviderItem,
        changedFields: NSFileProviderItemFields,
        contents: URL?,
        in domain: NSFileProviderDomain,
        container: ExtensionContainer,
        progress: Progress
    ) async throws -> NSFileProviderItem {
        guard let mountInfo = try await container.resolve(domain.identifier.rawValue) else {
            throw mappedError(.providerDomainNotFound)
        }
        guard let originalKey = key(from: item.itemIdentifier) else {
            throw mappedError(.noSuchItem)
        }
        var currentKey = originalKey
        // Rename = server-side copy + delete (mirrors the rename path
        // in the host's BrowserViewModel).
        if changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier) {
            let parentKey = key(from: item.parentItemIdentifier) ?? ""
            let newKey = parentKey + item.filename
            if newKey != originalKey {
                try await container.browser.copy(
                    account: mountInfo.account,
                    fromBucket: mountInfo.bucket,
                    fromKey: originalKey,
                    toBucket: mountInfo.bucket,
                    toKey: newKey,
                    metadata: nil
                )
                try await container.browser.delete(
                    account: mountInfo.account,
                    bucket: mountInfo.bucket,
                    keys: [originalKey]
                )
                currentKey = newKey
            }
        }
        if changedFields.contains(.contents), let contents {
            try await uploadFile(
                contents,
                account: mountInfo.account,
                bucket: mountInfo.bucket,
                key: currentKey,
                container: container,
                progress: progress
            )
        }
        let head = try await container.browser.head(
            account: mountInfo.account,
            bucket: mountInfo.bucket,
            key: currentKey
        )
        return ResolvedItem(
            identifier: identifier(for: currentKey),
            parent: parentIdentifier(for: currentKey),
            object: head
        )
    }

    // MARK: - Delete

    static func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        in domain: NSFileProviderDomain,
        container: ExtensionContainer
    ) async throws {
        guard let mountInfo = try await container.resolve(domain.identifier.rawValue) else {
            throw mappedError(.providerDomainNotFound)
        }
        guard let key = key(from: identifier), !key.isEmpty else {
            throw mappedError(.noSuchItem)
        }
        do {
            if key.hasSuffix("/") {
                // Codex high #4: folder identifiers represent a virtual
                // prefix in the bucket. Deleting only the `prefix/`
                // marker would leave every descendant orphaned in the
                // bucket while Finder reports success. Recursively
                // enumerate and batch-delete every key under the prefix
                // before completing.
                try await deleteRecursively(
                    prefix: key,
                    account: mountInfo.account,
                    bucket: mountInfo.bucket,
                    container: container
                )
            } else {
                try await container.browser.delete(
                    account: mountInfo.account,
                    bucket: mountInfo.bucket,
                    keys: [key]
                )
            }
        } catch {
            throw fileProviderError(error, fallback: .cannotSynchronize)
        }
    }

    /// Walk every common prefix and file under `prefix` and delete them
    /// in S3-safe batches. Uses the existing `S3Browsing.listObjects`
    /// continuation token; the S3 backend chunks 1000 keys per
    /// DeleteObjects request internally.
    private static func deleteRecursively(
        prefix: String,
        account: S3Account,
        bucket: String,
        container: ExtensionContainer
    ) async throws {
        var allKeys: [String] = [prefix]
        var queue: [String] = [prefix]
        while let next = queue.first {
            queue.removeFirst()
            var token: String? = nil
            repeat {
                try Task.checkCancellation()
                let page = try await container.browser.listObjects(
                    account: account,
                    bucket: bucket,
                    prefix: next,
                    continuationToken: token
                )
                for object in page.objects {
                    if object.isFolder {
                        queue.append(object.key)
                    }
                    allKeys.append(object.key)
                }
                token = page.continuationToken
                if !page.hasMore { token = nil }
            } while token != nil
        }
        try await container.browser.delete(
            account: account,
            bucket: bucket,
            keys: allKeys
        )
    }

    // MARK: - Transports

    /// Direct download bridge that bypasses the host's TransferManager
    /// queue. Picks S3 multipart for large objects automatically via
    /// Soto; Azure uses the existing ranged-parallel transporter.
    private static func downloadObject(
        account: S3Account,
        bucket: String,
        key: String,
        size: Int64,
        to localURL: URL,
        container: ExtensionContainer,
        progress: Progress
    ) async throws {
        switch account.provider.family {
        case .azureBlob:
            try await container.azureTransporter.download(
                account: account,
                container: bucket,
                blob: key,
                localURL: localURL,
                progress: { bytes, total in
                    Self.publish(progress: progress, bytes: bytes, total: total)
                }
            )
        case .s3:
            try await S3DirectFetch.download(
                account: account,
                bucket: bucket,
                key: key,
                size: size,
                to: localURL,
                factory: container.clientFactory
            )
            Self.publish(progress: progress, bytes: size, total: size)
        }
    }

    private static func uploadFile(
        _ url: URL,
        account: S3Account,
        bucket: String,
        key: String,
        container: ExtensionContainer,
        progress: Progress
    ) async throws {
        switch account.provider.family {
        case .azureBlob:
            try await container.azureTransporter.upload(
                account: account,
                container: bucket,
                blob: key,
                localURL: url,
                contentType: contentType(for: url),
                progress: { bytes, total in
                    Self.publish(progress: progress, bytes: bytes, total: total)
                }
            )
        case .s3:
            try await S3DirectFetch.upload(
                account: account,
                bucket: bucket,
                key: key,
                localURL: url,
                contentType: contentType(for: url),
                factory: container.clientFactory
            )
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            Self.publish(progress: progress, bytes: Int64(size), total: Int64(size))
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
        if let nsError = error as? NSError, nsError.domain == NSFileProviderErrorDomain {
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
        self.modificationDate = object.lastModified
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
        // call we do not expose. Codex medium #10: returning the
        // folder capabilities here let Finder offer a Delete that
        // would silently fail.
        if itemIdentifier == .rootContainer {
            return [.allowsContentEnumerating, .allowsAddingSubItems]
        }
        if isFolder {
            return [.allowsContentEnumerating, .allowsAddingSubItems, .allowsDeleting, .allowsRenaming]
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
