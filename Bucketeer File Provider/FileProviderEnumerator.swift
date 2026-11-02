//
//  FileProviderEnumerator.swift
//  Bucketeer File Provider
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
@preconcurrency import FileProvider
import BucketeerCore

/// Walks one prefix per call for the system enumerator. Pages through
/// the underlying provider's continuation tokens, surfacing folders as
/// `.folder`-content-type items so Finder recurses into them on demand.
///
/// Apple's contract:
/// - `enumerateItems(for:startingAt:)` finishes by calling
///   `finishEnumerating(upTo:)` with either `nil` (no more pages) or
///   the next `NSFileProviderPage` (a continuation cursor).
/// - Change tracking is not implemented in v1: `currentSyncAnchor` is a
///   fixed value and `enumerateChanges` reports no changes. Finder picks
///   up remote changes only when it re-enumerates a folder.
final class FileProviderEnumerator: NSObject, @unchecked Sendable, NSFileProviderEnumerator {
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

    /// Serialises task replacement, invalidation and observer delivery.
    /// Invariant: an observer is only called while `lock` is held and
    /// only if the publishing task's generation is still current, so
    /// once `invalidate()` (or a superseding enumeration) has taken the
    /// lock, the superseded task can no longer reach its observer. This
    /// is what makes the `@unchecked Sendable` conformance sound.
    private let lock = NSLock()
    /// Guarded by `lock`.
    private var generation: UInt64 = 0
    /// Guarded by `lock`.
    private var enumerationTask: Task<Void, Never>?

    func invalidate() {
        lock.withLock {
            generation &+= 1
            enumerationTask?.cancel()
            enumerationTask = nil
        }
    }

    func enumerateItems(
        for observer: NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) {
        let obs = UncheckedSendable(value: observer)
        lock.withLock {
            generation &+= 1
            let token = generation
            enumerationTask?.cancel()
            enumerationTask = Task {
                await self.enumerate(page: page, generation: token, observer: obs)
            }
        }
    }

    private func enumerate(
        page: NSFileProviderPage,
        generation token: UInt64,
        observer obs: UncheckedSendable<NSFileProviderEnumerationObserver>
    ) async {
        do {
            guard let mountInfo = try await extensionContainer.resolve(domain.identifier.rawValue) else {
                publish(token) {
                    obs.value.finishEnumeratingWithError(
                        FileProviderItemResolver.mappedError(.providerDomainNotFound)
                    )
                }
                return
            }
            // v1 reports the root listing as the working set; its items
            // keep their real parent, never the synthetic container.
            let isWorkingSet = containerIdentifier == .workingSet
            let parent: NSFileProviderItemIdentifier = isWorkingSet ? .rootContainer : containerIdentifier
            guard let prefix = isWorkingSet ? "" : FileProviderItemResolver.key(from: containerIdentifier) else {
                publish(token) {
                    obs.value.finishEnumeratingWithError(FileProviderItemResolver.mappedError(.noSuchItem))
                }
                return
            }
            let result = try await extensionContainer.browser.listObjects(
                account: mountInfo.account,
                bucket: mountInfo.bucket,
                prefix: prefix,
                continuationToken: continuationToken(from: page)
            )
            let items: [NSFileProviderItem] = result.objects.map { object in
                ResolvedItem(
                    identifier: FileProviderItemResolver.identifier(for: object.key),
                    parent: parent,
                    object: object
                )
            }
            let nextPage: NSFileProviderPage?
            if result.hasMore, let nextToken = result.continuationToken {
                nextPage = NSFileProviderPage(Data(nextToken.utf8))
            } else {
                nextPage = nil
            }
            publish(token) {
                obs.value.didEnumerate(items)
                obs.value.finishEnumerating(upTo: nextPage)
            }
        } catch {
            publish(token) {
                obs.value.finishEnumeratingWithError(
                    FileProviderItemResolver.fileProviderError(error, fallback: .serverUnreachable)
                )
            }
        }
    }

    /// Delivers to the observer only if `token` is still the current
    /// generation; see the invariant on `lock`.
    private func publish(_ token: UInt64, _ delivery: () -> Void) {
        lock.withLock {
            guard generation == token else { return }
            delivery()
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

/// Launders a non-Sendable value across a Swift 6 `sending` closure
/// boundary. Use only where the value is provably safe to transfer —
/// NSFileProvider observer and completion handler types are designed for
/// cross-thread invocation, so the @unchecked conformance is warranted.
struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
}
