//
//  FileProviderEnumerator.swift
//  Bucketeer File Provider
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import FileProvider
import BucketeerCore

/// Walks one prefix per call for the system enumerator. Pages through
/// the underlying provider's continuation tokens, surfacing folders as
/// `.folder`-content-type items so Finder recurses into them on demand.
///
/// Apple's contract:
/// - `enumerateItems(for:startingAt:)` finishes by calling
///   `finishEnumerating(upTo:)` with either `nil` (no more pages) or
///   the next `NSFileProviderPage` (a continuation cursor).
/// - `currentSyncAnchor` returns a monotonically-increasing token; we
///   emit a fresh anchor on every change so the system re-enumerates
///   the affected container after host-side writes.
/// - `enumerateChanges(for:from:)` is a no-op in v1 — pull-based; the
///   host signals the system via `NSFileProviderManager.signalEnumerator`
///   when a write through the host app should be reflected in Finder
///   (wired in Phase 9.5.1).
final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    let domain: NSFileProviderDomain
    let containerIdentifier: NSFileProviderItemIdentifier
    let extensionContainer: ExtensionContainer

    init(
        domain: NSFileProviderDomain,
        containerIdentifier: NSFileProviderItemIdentifier,
        extensionContainer: ExtensionContainer
    ) {
        self.domain = domain
        self.containerIdentifier = containerIdentifier
        self.extensionContainer = extensionContainer
        super.init()
    }

    func invalidate() {}

    func enumerateItems(
        for observer: NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) {
        Task {
            do {
                guard let mountInfo = try await extensionContainer.resolve(domain.identifier.rawValue) else {
                    observer.finishEnumeratingWithError(
                        FileProviderItemResolver.mappedError(.providerDomainNotFound)
                    )
                    return
                }
                let prefix = FileProviderItemResolver.key(from: containerIdentifier) ?? ""
                let token = continuationToken(from: page)
                let result = try await extensionContainer.browser.listObjects(
                    account: mountInfo.account,
                    bucket: mountInfo.bucket,
                    prefix: prefix,
                    continuationToken: token
                )
                let items: [NSFileProviderItem] = result.objects.map { object in
                    ResolvedItem(
                        identifier: FileProviderItemResolver.identifier(for: object.key),
                        parent: containerIdentifier,
                        object: object
                    )
                }
                observer.didEnumerate(items)
                let nextPage: NSFileProviderPage?
                if result.hasMore, let nextToken = result.continuationToken {
                    nextPage = NSFileProviderPage(Data(nextToken.utf8))
                } else {
                    nextPage = nil
                }
                observer.finishEnumerating(upTo: nextPage)
            } catch {
                observer.finishEnumeratingWithError(
                    FileProviderItemResolver.fileProviderError(error, fallback: .serverUnreachable)
                )
            }
        }
    }

    func enumerateChanges(
        for observer: NSFileProviderChangeObserver,
        from syncAnchor: NSFileProviderSyncAnchor
    ) {
        // v1 is pull-only — the host calls signalEnumerator after writes
        // to invalidate caches. Phase 9.5.1 wires push-style change
        // detection when we add the optional working-set enumerator.
        observer.finishEnumeratingChanges(upTo: syncAnchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        // Stable anchor — per Apple's contract the anchor represents
        // the current change state. Bucketeer holds no server-side
        // change log (S3 / Azure don't push), so we keep one fixed
        // value per process and rely on the host calling
        // `NSFileProviderManager.signalEnumerator(for:)` after every
        // bucket-write the host performs. Finder also re-enumerates on
        // user-initiated refresh (⌘R, scrolling to top) which produces
        // a fresh `enumerateItems` call regardless of the anchor.
        completionHandler(NSFileProviderSyncAnchor(Data("bucketeer-fp-v1".utf8)))
    }

    // MARK: - Pagination

    private func continuationToken(from page: NSFileProviderPage) -> String? {
        // The initial pages reserved by the system (`initialPageSortedByName`,
        // `initialPageSortedByDate`) never decode to a UTF-8 string; treat
        // them as "no token".
        if page.rawValue == NSFileProviderPage.initialPageSortedByName as Data ||
           page.rawValue == NSFileProviderPage.initialPageSortedByDate as Data {
            return nil
        }
        return String(data: page.rawValue, encoding: .utf8)
    }
}
