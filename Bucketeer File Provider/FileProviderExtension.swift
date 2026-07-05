//
//  FileProviderExtension.swift
//  Bucketeer File Provider
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
@preconcurrency import FileProvider
import BucketeerCore

/// `NSFileProviderReplicatedExtension` is the modern (macOS 11+) hook
/// that exposes a remote filesystem to Finder under Locations. macOS
/// replicates files on disk in the user's container; the extension
/// provides enumeration, fetch, create, modify, delete primitives.
///
/// **Bucketeer model:** one `NSFileProviderDomain` per mounted bucket.
/// The identifier `"<accountID>::<bucket>"` is parsed by
/// `ExtensionContainer.resolve(_:)` on every call so the right S3 /
/// Azure account is targeted.
final class FileProviderExtension: NSObject, @unchecked Sendable, NSFileProviderReplicatedExtension {

    let domain: NSFileProviderDomain
    let container: ExtensionContainer?
    let containerError: Error?

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        do {
            self.container = try ExtensionContainer()
            self.containerError = nil
        } catch {
            self.container = nil
            self.containerError = error
        }
        super.init()
    }

    func invalidate() {
        // No connections to drain — S3 clients are pooled per-account
        // inside the shared S3ClientFactory and the URL session is
        // singleton.
    }

    // MARK: - Item

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        let ch = UncheckedSendable(value: completionHandler)
        let task = Task {
            let completionHandler = ch.value
            guard let container = container else {
                completionHandler(nil, self.containerError ?? Self.notProvisionedError())
                return
            }
            do {
                let item = try await FileProviderItemResolver.resolve(
                    identifier: identifier,
                    in: domain,
                    container: container
                )
                try Task.checkCancellation()
                completionHandler(item, nil)
                progress.completedUnitCount = 1
            } catch is CancellationError {
                completionHandler(nil, FileProviderItemResolver.mappedError(.serverUnreachable))
            } catch {
                completionHandler(nil, error)
            }
        }
        // Codex high #8: bridge Progress cancellation (Finder ⌘. or
        // a system-initiated cancel) to the orchestrating Task so the
        // network work actually stops instead of running to completion
        // and calling the completion handler late.
        progress.cancellationHandler = { task.cancel() }
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
        let ch = UncheckedSendable(value: completionHandler)
        let task = Task {
            let completionHandler = ch.value
            guard let container = container else {
                completionHandler(nil, nil, self.containerError ?? Self.notProvisionedError())
                return
            }
            do {
                let result = try await FileProviderItemResolver.fetchContents(
                    identifier: itemIdentifier,
                    in: domain,
                    container: container,
                    progress: progress
                )
                // Cancellation after a completed download must clean
                // up the staging file — `try Task.checkCancellation()`
                // used to throw past the result and orphan it in tmp.
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: result.url)
                    completionHandler(nil, nil, FileProviderItemResolver.mappedError(.serverUnreachable))
                    return
                }
                completionHandler(result.url, result.item, nil)
            } catch is CancellationError {
                completionHandler(nil, nil, FileProviderItemResolver.mappedError(.serverUnreachable))
            } catch {
                completionHandler(nil, nil, error)
            }
        }
        progress.cancellationHandler = { task.cancel() }
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
        let ch = UncheckedSendable(value: completionHandler)
        let task = Task {
            let completionHandler = ch.value
            guard let container = container else {
                completionHandler(nil, [], false, self.containerError ?? Self.notProvisionedError())
                return
            }
            do {
                let created = try await FileProviderItemResolver.createItem(
                    template: itemTemplate,
                    contents: url,
                    in: domain,
                    container: container,
                    progress: progress
                )
                try Task.checkCancellation()
                completionHandler(created, [], false, nil)
            } catch is CancellationError {
                completionHandler(nil, [], false, FileProviderItemResolver.mappedError(.serverUnreachable))
            } catch {
                completionHandler(nil, [], false, error)
            }
        }
        progress.cancellationHandler = { task.cancel() }
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
        let ch = UncheckedSendable(value: completionHandler)
        let task = Task {
            let completionHandler = ch.value
            guard let container = container else {
                completionHandler(nil, [], false, self.containerError ?? Self.notProvisionedError())
                return
            }
            do {
                let modified = try await FileProviderItemResolver.modifyItem(
                    item: item,
                    changedFields: changedFields,
                    contents: newContents,
                    in: domain,
                    container: container,
                    progress: progress
                )
                try Task.checkCancellation()
                completionHandler(modified, [], false, nil)
            } catch is CancellationError {
                completionHandler(nil, [], false, FileProviderItemResolver.mappedError(.serverUnreachable))
            } catch {
                completionHandler(nil, [], false, error)
            }
        }
        progress.cancellationHandler = { task.cancel() }
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
        let ch = UncheckedSendable(value: completionHandler)
        let task = Task {
            let completionHandler = ch.value
            guard let container = container else {
                completionHandler(self.containerError ?? Self.notProvisionedError())
                return
            }
            do {
                try await FileProviderItemResolver.deleteItem(
                    identifier: identifier,
                    in: domain,
                    container: container
                )
                try Task.checkCancellation()
                completionHandler(nil)
                progress.completedUnitCount = 1
            } catch is CancellationError {
                completionHandler(FileProviderItemResolver.mappedError(.serverUnreachable))
            } catch {
                completionHandler(error)
            }
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    // MARK: - Enumeration

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        guard let container = container else {
            throw containerError ?? Self.notProvisionedError()
        }
        return FileProviderEnumerator(
            domain: domain,
            containerIdentifier: containerItemIdentifier,
            extensionContainer: container
        )
    }

    // MARK: - Helpers

    private static func notProvisionedError() -> Error {
        NSError(
            domain: NSFileProviderErrorDomain,
            code: NSFileProviderError.providerNotFound.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Bucketeer File Provider container not initialised. Verify the App Group entitlement and that the host app has been launched at least once."]
        )
    }
}

/// Launders a non-Sendable value across a Swift 6 `sending` closure
/// boundary. Use only where the value is provably safe to transfer —
/// NSFileProvider completion handler blocks are designed for cross-thread
/// invocation, so the @unchecked conformance is warranted.
private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
}
