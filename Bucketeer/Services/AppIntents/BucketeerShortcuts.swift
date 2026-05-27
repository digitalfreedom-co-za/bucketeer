//
//  BucketeerShortcuts.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import AppIntents

/// AppShortcuts provider. Phase 13.12. Surfaces Bucketeer's intents
/// in the Shortcuts app and Spotlight without requiring the user to
/// build a manual shortcut for each one. The system auto-binds the
/// trigger phrases below to the intent so Siri / Spotlight can
/// invoke them directly.
struct BucketeerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ListBucketsIntent(),
            phrases: [
                "List buckets in \(.applicationName)",
                "Show my \(.applicationName) buckets"
            ],
            shortTitle: "List buckets",
            systemImageName: "shippingbox"
        )
        AppShortcut(
            intent: GeneratePresignedURLIntent(),
            phrases: [
                "Generate a share link with \(.applicationName)",
                "Sign a URL with \(.applicationName)"
            ],
            shortTitle: "Generate URL",
            systemImageName: "link"
        )
        AppShortcut(
            intent: UploadFileIntent(),
            phrases: [
                "Upload a file with \(.applicationName)",
                "Send to bucket with \(.applicationName)"
            ],
            shortTitle: "Upload file",
            systemImageName: "arrow.up.circle"
        )
        // RunSyncJobIntent now takes a SyncJobEntity parameter
        // (Phase 14 / Codex R2 low follow-up). The picker handles
        // the visible side; we just need to expose the intent.
        AppShortcut(
            intent: RunSyncJobIntent(),
            phrases: [
                "Run a sync with \(.applicationName)",
                "Trigger \(.applicationName) sync"
            ],
            shortTitle: "Run sync",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
