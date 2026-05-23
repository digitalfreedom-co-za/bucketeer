//
//  FileProviderExtension.swift
//  Bucketeer File Provider
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import FileProvider
import UniformTypeIdentifiers

/// `NSFileProviderReplicatedExtension` is the modern (macOS 11+) hook
/// that exposes a remote filesystem to Finder under Locations. macOS
/// replicates files on disk in the user's container; the extension
/// provides enumeration, fetch, create, modify, delete primitives.
///
/// **Bucketeer model:** one `NSFileProviderDomain` per mounted bucket.
/// The identifier looks like `"<accountID>::<bucket>"`, encoded by
/// `MountController.domainIdentifier(accountID:bucket:)`. On `init` we
/// parse the identifier, resolve the corresponding `S3Account` from the
/// shared SwiftData store, and load credentials from the shared
/// Keychain access group.
///
/// This file is part of a separate Xcode target — see
/// `PHASE_9_SETUP.md` at the repo root for the manual steps to wire
/// the target into Bucketeer.xcodeproj.
final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {

    let domain: NSFileProviderDomain
    /// Best-effort cached resolution of the (account, bucket) tuple.
    /// The extension is re-created by the system on each unmount /
    /// re-mount, so the cache is per-mount-session.
    let mountInfo: (accountID: UUID, bucket: String)?

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        self.mountInfo = Self.parseDomainIdentifier(domain.identifier)
        super.init()
    }

    func invalidate() {
        // No connections to drain in v1 — `S3` and `URLSession` are stateless.
    }

    // MARK: - Item resolution

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        Task {
            do {
                let item = try await FileProviderItemResolver.resolve(
                    identifier: identifier,
                    in: domain
                )
                completionHandler(item, nil)
                progress.completedUnitCount = 1
            } catch {
                completionHandler(nil, error)
            }
        }
        return progress
    }

    // MARK: - Fetch

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 100)
        Task {
            do {
                let result = try await FileProviderItemResolver.fetchContents(
                    identifier: itemIdentifier,
                    in: domain,
                    progress: progress
                )
                completionHandler(result.url, result.item, nil)
            } catch {
                completionHandler(nil, nil, error)
            }
        }
        return progress
    }

    // MARK: - Create

    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 100)
        Task {
            do {
                let created = try await FileProviderItemResolver.createItem(
                    template: itemTemplate,
                    contents: url,
                    in: domain,
                    progress: progress
                )
                completionHandler(created, [], false, nil)
            } catch {
                completionHandler(nil, [], false, error)
            }
        }
        return progress
    }

    // MARK: - Modify

    func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion version: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 100)
        Task {
            do {
                let modified = try await FileProviderItemResolver.modifyItem(
                    item: item,
                    changedFields: changedFields,
                    contents: newContents,
                    in: domain,
                    progress: progress
                )
                completionHandler(modified, [], false, nil)
            } catch {
                completionHandler(nil, [], false, error)
            }
        }
        return progress
    }

    // MARK: - Delete

    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion version: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        Task {
            do {
                try await FileProviderItemResolver.deleteItem(
                    identifier: identifier,
                    in: domain
                )
                completionHandler(nil)
                progress.completedUnitCount = 1
            } catch {
                completionHandler(error)
            }
        }
        return progress
    }

    // MARK: - Enumeration

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        FileProviderEnumerator(domain: domain, container: containerItemIdentifier)
    }

    // MARK: - Helpers

    static func parseDomainIdentifier(_ identifier: NSFileProviderDomainIdentifier) -> (UUID, String)? {
        let raw = identifier.rawValue
        guard let separatorRange = raw.range(of: "::") else { return nil }
        let idPart = String(raw[..<separatorRange.lowerBound])
        let bucket = String(raw[separatorRange.upperBound...])
        guard let uuid = UUID(uuidString: idPart) else { return nil }
        return (uuid, bucket)
    }
}
