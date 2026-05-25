//
//  DeepLinkRouter.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import AppKit
import SwiftUI
import BucketeerCore

/// Consumes parsed `BucketeerDeepLink` values and routes the app
/// accordingly: focuses the right window, navigates the browser into
/// the bucket/prefix, opens the right system window. Phase 13.11.
///
/// The router lives on the main actor and depends on the host's view
/// models. It also installs an `NSAppleEventManager` handler at
/// construction so URLs opened while the App is already running
/// reach us even when the app was first launched in `.accessory`
/// (menu-bar) mode without a Dock icon.
@MainActor
@Observable
final class DeepLinkRouter {
    private let browser: BrowserViewModel
    private let accountStore: any AccountStoring
    /// Monotonically increasing route token — Codex audit R2
    /// (medium): when the user pastes several `bucketeer://` URLs
    /// rapidly, each spawns an async load. Without a token, the
    /// loads can resolve out of order and leave the browser on a
    /// stale destination. Every async navigation checks its
    /// captured token against the current value and bails when
    /// stale.
    private var routeToken: UInt64 = 0

    init(browser: BrowserViewModel, accountStore: any AccountStoring) {
        self.browser = browser
        self.accountStore = accountStore
        registerAppleEventHandler()
    }

    /// Apply one deep link. The caller (SwiftUI's `.onOpenURL`)
    /// already handed us a parsed URL — this routine resolves any
    /// IDs against the live account list and updates view-model
    /// state.
    func handle(_ link: BucketeerDeepLink, openWindow: OpenWindowAction) {
        NSApp.activate(ignoringOtherApps: true)
        // Bump the token *first* so any in-flight navigation from
        // an earlier link sees a stale value and bails.
        routeToken &+= 1
        let token = routeToken
        switch link {
        case .account(let id):
            openWindow(id: "main")
            Task { await navigateToBucket(accountID: id, bucket: nil, prefix: "", token: token) }
        case .bucket(let id, let bucket, let prefix):
            openWindow(id: "main")
            Task { await navigateToBucket(accountID: id, bucket: bucket, prefix: prefix, token: token) }
        case .object(let id, let bucket, let key):
            openWindow(id: "main")
            let prefix = Self.derivePrefix(fromKey: key)
            Task { await navigateToBucket(accountID: id, bucket: bucket, prefix: prefix, token: token) }
        case .syncJob:
            openWindow(id: "main")
        case .activity:
            openWindow(id: "activity")
        case .trash:
            openWindow(id: "trash")
        }
    }

    /// Convenience that parses + handles in one shot.
    func handle(url: URL, openWindow: OpenWindowAction) {
        guard let link = BucketeerDeepLink(url: url) else { return }
        handle(link, openWindow: openWindow)
    }

    // MARK: - Private

    private func navigateToBucket(
        accountID: UUID,
        bucket: String?,
        prefix: String,
        token: UInt64
    ) async {
        do {
            let accounts = try await accountStore.all()
            // Codex audit R2 (medium): bail if a newer handle()
            // bumped the token while we were awaiting accountStore.
            guard token == routeToken else { return }
            guard let account = accounts.first(where: { $0.id == accountID }) else { return }
            browser.account = account
            browser.bucket = bucket
            browser.prefix = prefix
            if bucket == nil {
                await browser.loadBuckets()
            } else {
                await browser.loadObjectsResetting()
            }
        } catch {
            // Best-effort — bad deep link is ignored.
        }
    }

    /// Carve the prefix from a fully-qualified object key so the
    /// browser lands in the same folder as the linked object even
    /// when we can't open the file directly (which `bucketeer://`
    /// intentionally doesn't do).
    private static func derivePrefix(fromKey key: String) -> String {
        guard let lastSlash = key.lastIndex(of: "/") else { return "" }
        return String(key[..<key.index(after: lastSlash)])
    }

    /// Register the `kAEGetURL` handler so URLs opened while the
    /// App is already running come through even when SwiftUI's
    /// `.onOpenURL` is bypassed (e.g. when the App is in
    /// `.accessory` activation policy).
    private func registerAppleEventHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent reply: NSAppleEventDescriptor
    ) {
        guard let raw = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: raw),
              let link = BucketeerDeepLink(url: url) else { return }
        // We don't have an OpenWindowAction here — post a
        // Notification that the App scene picks up and re-routes
        // through the normal SwiftUI environment.
        NotificationCenter.default.post(
            name: .bucketeerDeepLinkReceived,
            object: link
        )
    }
}

extension Notification.Name {
    /// Posted by `DeepLinkRouter` when an external URL arrives via
    /// the AppleEvent handler. The App scene listens and routes it
    /// through SwiftUI's `OpenWindowAction`.
    static let bucketeerDeepLinkReceived = Notification.Name(
        "za.co.digitalfreedom.bucketeer.deepLinkReceived"
    )
}
