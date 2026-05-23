//
//  FileProviderItemResolver.swift
//  Bucketeer File Provider
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import FileProvider
import UniformTypeIdentifiers

/// Concentrates the actual S3/Azure traffic for the File Provider
/// extension. Kept separate from `FileProviderExtension` so the callback
/// shells stay short and the testable surface — these async functions —
/// stays small.
///
/// **v1 status:** this file provides the orchestration scaffolding so
/// the extension target compiles and registers cleanly. The actual S3
/// and Azure traffic is wired in v1.1 — the host app's `AppContainer`
/// composition would need to be factored into a `Bucketeer Core`
/// framework first (spec §3.3, Phase 9.5) so the extension can share
/// `S3ClientFactory`, `AzureBlobObjectStore`, `KeychainStore`, and
/// `AccountStore` with the host. Until then mounts surface as empty
/// folders in Finder and write attempts fail gracefully.
enum FileProviderItemResolver {

    static func resolve(
        identifier: NSFileProviderItemIdentifier,
        in domain: NSFileProviderDomain
    ) async throws -> NSFileProviderItem {
        if identifier == .rootContainer {
            return PlaceholderItem.root(domain: domain)
        }
        return PlaceholderItem(
            identifier: identifier,
            parent: .rootContainer,
            name: identifier.rawValue,
            isFolder: false
        )
    }

    struct FetchResult {
        let url: URL
        let item: NSFileProviderItem
    }

    static func fetchContents(
        identifier: NSFileProviderItemIdentifier,
        in domain: NSFileProviderDomain,
        progress: Progress
    ) async throws -> FetchResult {
        // The system hands us a target URL in the user's container; we
        // fill it with the object's bytes via the S3/Azure transport.
        // Wired in v1.1 once the Core framework split is done.
        progress.completedUnitCount = progress.totalUnitCount
        throw NSError(
            domain: NSFileProviderErrorDomain,
            code: NSFileProviderError.serverUnreachable.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Bucketeer File Provider fetch not yet wired (v1.1)."]
        )
    }

    static func createItem(
        template: NSFileProviderItem,
        contents: URL?,
        in domain: NSFileProviderDomain,
        progress: Progress
    ) async throws -> NSFileProviderItem {
        progress.completedUnitCount = progress.totalUnitCount
        throw NSError(
            domain: NSFileProviderErrorDomain,
            code: NSFileProviderError.cannotSynchronize.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Bucketeer File Provider create not yet wired (v1.1)."]
        )
    }

    static func modifyItem(
        item: NSFileProviderItem,
        changedFields: NSFileProviderItemFields,
        contents: URL?,
        in domain: NSFileProviderDomain,
        progress: Progress
    ) async throws -> NSFileProviderItem {
        progress.completedUnitCount = progress.totalUnitCount
        throw NSError(
            domain: NSFileProviderErrorDomain,
            code: NSFileProviderError.cannotSynchronize.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Bucketeer File Provider modify not yet wired (v1.1)."]
        )
    }

    static func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        in domain: NSFileProviderDomain
    ) async throws {
        throw NSError(
            domain: NSFileProviderErrorDomain,
            code: NSFileProviderError.cannotSynchronize.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Bucketeer File Provider delete not yet wired (v1.1)."]
        )
    }
}

/// Minimal `NSFileProviderItem` implementation used until the Core
/// framework split lands. Conforms to the protocol so the system has
/// something to render; metadata is best-effort.
final class PlaceholderItem: NSObject, NSFileProviderItem {
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let isFolder: Bool

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
        super.init()
    }

    static func root(domain: NSFileProviderDomain) -> PlaceholderItem {
        PlaceholderItem(
            identifier: .rootContainer,
            parent: .rootContainer,
            name: domain.displayName,
            isFolder: true
        )
    }

    var capabilities: NSFileProviderItemCapabilities {
        isFolder ? .allowsContentEnumerating : [.allowsReading, .allowsDeleting]
    }

    var contentType: UTType {
        isFolder ? .folder : .data
    }

    var itemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(
            contentVersion: Data("v1".utf8),
            metadataVersion: Data("v1".utf8)
        )
    }
}
