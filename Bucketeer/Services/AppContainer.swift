//
//  AppContainer.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation
import SwiftData

/// Composition root. Holds the long-lived services and root view models
/// for the host app. Created once at launch and injected into the
/// SwiftUI environment.
@MainActor
@Observable
final class AppContainer {
    let modelContainer: ModelContainer
    let keychainStore: KeychainStoring
    let accountStore: AccountStoring
    let clientFactory: S3ClientFactory
    let azureCredentialsCache: AzureCredentialsCache
    let azureTransporter: AzureBlobTransporter
    /// Routed `S3Browsing` facade — picks S3 or Azure per-account.
    let s3Browser: S3Browsing
    let transferManager: TransferManager
    let previewCache: PreviewCache
    let dragDropCoordinator: DragDropCoordinator
    let activationController: AppActivationController
    let mountController: MountController
    let syncJobStore: SyncJobStoring
    let syncEngine: SyncEngine
    let accountListViewModel: AccountListViewModel
    let browserViewModel: BrowserViewModel
    let transferQueueViewModel: TransferQueueViewModel
    let syncJobListViewModel: SyncJobListViewModel

    init() throws {
        let storeURL = Self.resolveStoreURL()
        let schema = Schema([S3AccountRecord.self, SyncJobRecord.self])
        let configuration = ModelConfiguration(
            "Bucketeer",
            schema: schema,
            url: storeURL
        )
        let modelContainer = try ModelContainer(
            for: schema,
            configurations: configuration
        )
        Self.runMigrations(modelContainer)
        let keychainStore = KeychainStore(
            service: AppEnvironment.keychainService,
            accessGroup: nil // Shared access group is added in Phase 9 with the File Provider extension.
        )
        let accountStore = AccountStore(modelContainer: modelContainer)
        let clientFactory = S3ClientFactory(keychainStore: keychainStore)
        let azureCredentialsCache = AzureCredentialsCache(keychainStore: keychainStore)
        let azureObjectStore = AzureBlobObjectStore(credentialsCache: azureCredentialsCache)
        let azureTransporter = AzureBlobTransporter(credentialsCache: azureCredentialsCache)
        let s3ObjectStore = S3Service(factory: clientFactory)
        let router = ProviderRouter(s3: s3ObjectStore, azure: azureObjectStore)
        let transferManager = TransferManager(
            factory: clientFactory,
            azure: azureTransporter
        )
        let previewCache = PreviewCache(
            downloader: PreviewDownloader(
                s3Factory: clientFactory,
                azureTransporter: azureTransporter
            )
        )

        self.modelContainer = modelContainer
        self.keychainStore = keychainStore
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        self.azureCredentialsCache = azureCredentialsCache
        self.azureTransporter = azureTransporter
        self.s3Browser = router
        self.transferManager = transferManager
        self.previewCache = previewCache
        self.accountListViewModel = AccountListViewModel(
            accountStore: accountStore,
            keychainStore: keychainStore,
            clientFactory: clientFactory,
            azureCredentialsCache: azureCredentialsCache,
            transferManager: transferManager
        )
        self.browserViewModel = BrowserViewModel(
            s3Browser: router,
            accountStore: accountStore
        )
        self.transferQueueViewModel = TransferQueueViewModel(
            transferManager: transferManager
        )
        self.transferQueueViewModel.startObserving()
        self.dragDropCoordinator = DragDropCoordinator(
            s3Browser: router,
            transferManager: transferManager,
            transferQueue: self.transferQueueViewModel,
            accountStore: accountStore
        )
        self.activationController = AppActivationController()
        let mountController = MountController()
        self.mountController = mountController
        Task { @MainActor [mountController] in
            await mountController.refresh()
        }
        let syncJobStore = SyncJobStore(modelContainer: modelContainer)
        let syncEngine = SyncEngine(
            accountStore: accountStore,
            jobStore: syncJobStore,
            browser: router,
            transferManager: transferManager
        )
        self.syncJobStore = syncJobStore
        self.syncEngine = syncEngine
        self.syncJobListViewModel = SyncJobListViewModel(
            jobStore: syncJobStore,
            engine: syncEngine,
            accountStore: accountStore
        )
        Task { @MainActor [syncJobListViewModel = self.syncJobListViewModel] in
            await syncJobListViewModel.bootstrap()
        }
    }

    /// One-shot data migrations that run at every launch. Each step is
    /// idempotent and cheap so re-running on every launch is safe.
    ///
    /// Current migrations:
    /// - **Civo path-style**: the original v1 default for Civo accounts
    ///   was virtual-host addressing, which fails DNS resolution
    ///   (`NoSuchRecord`) because Civo serves no `*.objectstore.<region>.civo.com`
    ///   wildcard. Flip any pre-existing Civo records that still carry
    ///   the old default so users do not have to edit each account by
    ///   hand.
    private static func runMigrations(_ container: ModelContainer) {
        let context = ModelContext(container)
        do {
            let civoRaw = S3Provider.civo.rawValue
            let predicate = #Predicate<S3AccountRecord> {
                $0.providerRaw == civoRaw && $0.usesPathStyle == false
            }
            let records = try context.fetch(FetchDescriptor(predicate: predicate))
            for record in records {
                record.usesPathStyle = true
            }
            if !records.isEmpty {
                try context.save()
            }
        } catch {
            // Best-effort — a migration failure should never block app launch.
        }
    }

    /// Resolve the SwiftData store URL. When the App Group entitlement
    /// is provisioned the store moves into the shared container so the
    /// File Provider extension (Phase 9) can read account metadata.
    /// Falls back to the sandbox Application Support path otherwise.
    ///
    /// A one-shot migration copies the legacy sandbox store into the
    /// group container the first time both paths are available. Idempotent
    /// — if the group store already exists we just use it and leave the
    /// sandbox copy in place as a fallback.
    private static func resolveStoreURL() -> URL {
        let sandboxURL = sandboxStoreURL()
        guard let groupContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppEnvironment.appGroupIdentifier
        ) else {
            return sandboxURL
        }
        let groupURL = groupContainer.appending(path: AppEnvironment.swiftDataStoreFileName)
        if !FileManager.default.fileExists(atPath: groupURL.path),
           FileManager.default.fileExists(atPath: sandboxURL.path) {
            // Copy the legacy store into the group container so the
            // extension sees the user's existing accounts.
            try? FileManager.default.copyItem(at: sandboxURL, to: groupURL)
            // The store has two sidecar files (`-shm`, `-wal`) when SQLite
            // is in WAL mode — copy them if present so the migration is
            // atomic from SwiftData's perspective.
            for suffix in ["-shm", "-wal"] {
                let src = sandboxURL.deletingLastPathComponent()
                    .appending(path: AppEnvironment.swiftDataStoreFileName + suffix)
                let dst = groupContainer
                    .appending(path: AppEnvironment.swiftDataStoreFileName + suffix)
                if FileManager.default.fileExists(atPath: src.path) {
                    try? FileManager.default.copyItem(at: src, to: dst)
                }
            }
        }
        return groupURL
    }

    private static func sandboxStoreURL() -> URL {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.documentsDirectory
        return support.appending(path: AppEnvironment.swiftDataStoreFileName)
    }
}
