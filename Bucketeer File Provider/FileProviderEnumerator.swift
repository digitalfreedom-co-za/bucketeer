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
/// - Changes are reported by the working-set enumerator: it lists every
///   folder Finder has opened again and diffs against the last listing
///   (`FinderChangeTracker`). Folder enumerators answer a change request
///   with `syncAnchorExpired`, which makes the system list the folder
///   again. The host signals the working set when the user refreshes.
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
    /// Same scheme for change enumeration, kept apart so a change
    /// request never cancels an item enumeration (whose observer would
    /// then never finish). Guarded by `lock`.
    private var changeGeneration: UInt64 = 0
    /// Guarded by `lock`.
    private var changeTask: Task<Void, Never>?

    func invalidate() {
        lock.withLock {
            generation &+= 1
            enumerationTask?.cancel()
            enumerationTask = nil
            changeGeneration &+= 1
            changeTask?.cancel()
            changeTask = nil
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
            if !isWorkingSet {
                await FinderChangeTracker.shared.track(prefix: prefix, domain: domain.identifier.rawValue)
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

    private func publishChange(_ token: UInt64, _ delivery: () -> Void) {
        lock.withLock {
            guard changeGeneration == token else { return }
            delivery()
        }
    }

    func enumerateChanges(
        for observer: NSFileProviderChangeObserver,
        from syncAnchor: NSFileProviderSyncAnchor
    ) {
        let obs = UncheckedSendable(value: observer)
        guard containerIdentifier == .workingSet else {
            obs.value.finishEnumeratingWithError(FileProviderItemResolver.mappedError(.syncAnchorExpired))
            return
        }
        lock.withLock {
            changeGeneration &+= 1
            let token = changeGeneration
            changeTask?.cancel()
            changeTask = Task {
                await self.reportChanges(since: syncAnchor, generation: token, observer: obs)
            }
        }
    }

    private func reportChanges(
        since syncAnchor: NSFileProviderSyncAnchor,
        generation token: UInt64,
        observer obs: UncheckedSendable<NSFileProviderChangeObserver>
    ) async {
        do {
            guard let mountInfo = try await extensionContainer.resolve(domain.identifier.rawValue) else {
                publishChange(token) {
                    obs.value.finishEnumeratingWithError(FileProviderItemResolver.mappedError(.providerDomainNotFound))
                }
                return
            }
            let changes = try await FinderChangeTracker.shared.changes(
                since: String(decoding: syncAnchor.rawValue, as: UTF8.self),
                domain: domain.identifier.rawValue,
                list: lister(account: mountInfo.account, bucket: mountInfo.bucket)
            )
            let updated: [NSFileProviderItem] = changes.updated.map { object in
                ResolvedItem(
                    identifier: FileProviderItemResolver.identifier(for: object.key),
                    parent: FileProviderItemResolver.parentIdentifier(for: object.key),
                    object: object
                )
            }
            let deleted = changes.deleted.map(FileProviderItemResolver.identifier(for:))
            publishChange(token) {
                if !updated.isEmpty { obs.value.didUpdate(updated) }
                if !deleted.isEmpty { obs.value.didDeleteItems(withIdentifiers: deleted) }
                obs.value.finishEnumeratingChanges(
                    upTo: NSFileProviderSyncAnchor(Data(changes.anchor.utf8)),
                    moreComing: false
                )
            }
        } catch FinderChangeTracker.TrackerError.anchorExpired {
            publishChange(token) {
                obs.value.finishEnumeratingWithError(FileProviderItemResolver.mappedError(.syncAnchorExpired))
            }
        } catch {
            publishChange(token) {
                obs.value.finishEnumeratingWithError(
                    FileProviderItemResolver.fileProviderError(error, fallback: .serverUnreachable)
                )
            }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let ch = UncheckedSendable(value: completionHandler)
        // Folder enumerators expire every anchor (see enumerateChanges),
        // so any fresh value will do.
        guard containerIdentifier == .workingSet else {
            ch.value(NSFileProviderSyncAnchor(Data(UUID().uuidString.utf8)))
            return
        }
        Task {
            guard let mountInfo = try? await extensionContainer.resolve(domain.identifier.rawValue),
                  let anchor = try? await FinderChangeTracker.shared.currentAnchor(
                      domain: domain.identifier.rawValue,
                      list: lister(account: mountInfo.account, bucket: mountInfo.bucket)
                  )
            else {
                ch.value(nil)
                return
            }
            ch.value(NSFileProviderSyncAnchor(Data(anchor.utf8)))
        }
    }

    /// All pages of one folder level.
    private func lister(account: S3Account, bucket: String) -> FinderChangeTracker.Lister {
        let browser = extensionContainer.browser
        return { prefix in
            var objects: [S3Object] = []
            var token: String?
            repeat {
                try Task.checkCancellation()
                let page = try await browser.listObjects(
                    account: account,
                    bucket: bucket,
                    prefix: prefix,
                    continuationToken: token
                )
                objects += page.objects
                token = page.hasMore ? page.continuationToken : nil
            } while token != nil
            return objects
        }
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
