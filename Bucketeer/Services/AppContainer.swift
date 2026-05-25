//
//  AppContainer.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation
import SwiftData
import BucketeerCore

/// Composition root. Holds the long-lived services and root view models
/// for the host app. Created once at launch and injected into the
/// SwiftUI environment.
@MainActor
@Observable
final class AppContainer {
    /// Process-wide singleton handle. Phase 13.12 — App Intents
    /// execute inside the host process and need access to the live
    /// container without having to rebuild SwiftData / Keychain.
    /// `BucketeerApp.init` sets this immediately after construction;
    /// nothing else writes to it. `nonisolated(unsafe)` because the
    /// pointer is set once at launch and only read on the main
    /// actor afterwards.
    nonisolated(unsafe) static var shared: AppContainer?

    let modelContainer: ModelContainer
    /// Host-only audit-log container — kept separate from the App
    /// Group container because the File Provider extension has no
    /// reason to load this schema. Phase 13.1.
    let activityContainer: ModelContainer
    /// Phase 13.4 — separate SwiftData container for the soft-delete
    /// trash. Kept out of both the App Group store and the activity
    /// store because trash housekeeping is independent.
    let trashContainer: ModelContainer
    /// Phase 13.8 — auto-tag rule store, host-only.
    let autoTagContainer: ModelContainer
    /// Phase 13.10 — resumable-upload checkpoints, host-only.
    let checkpointContainer: ModelContainer
    let checkpointStore: any CheckpointStoring
    /// Shared bandwidth throttle. Phase 13.2.
    let bandwidthLimiter: BandwidthLimiter
    let bandwidthSettings: BandwidthSettings
    let keychainStore: any KeychainStoring
    let accountStore: any AccountStoring
    let clientFactory: S3ClientFactory
    let azureCredentialsCache: AzureCredentialsCache
    let azureTransporter: AzureBlobTransporter
    /// Routed `S3Browsing` facade — picks S3 or Azure per-account.
    let s3Browser: any S3Browsing
    let transferManager: TransferManager
    let previewCache: PreviewCache
    let dragDropCoordinator: DragDropCoordinator
    let activationController: AppActivationController
    let mountController: MountController
    let entitlementManager: EntitlementManager
    let syncJobStore: any SyncJobStoring
    let syncEngine: SyncEngine
    let activityLog: any ActivityLogging
    /// Phase 13.4 — soft-delete trash.
    let trashStore: any TrashStoring
    let trashCoordinator: TrashCoordinator
    let trashSettings: TrashSettings
    /// Phase 13.8 — auto-tagging.
    let autoTagStore: any AutoTagRuleStoring
    let autoTagCoordinator: AutoTagCoordinator
    let autoTagRulesViewModel: AutoTagRulesViewModel
    /// Phase 13.11 — deep-link router.
    let deepLinkRouter: DeepLinkRouter
    /// Phase 13.13 — Spotlight indexer + its opt-in toggle.
    let spotlightIndexer: SpotlightIndexer
    let spotlightSettings: SpotlightSettings
    /// Phase 13.14 — cross-account copy / move.
    let crossAccountCopyCoordinator: CrossAccountCopyCoordinator
    let accountListViewModel: AccountListViewModel
    let browserViewModel: BrowserViewModel
    let transferQueueViewModel: TransferQueueViewModel
    let syncJobListViewModel: SyncJobListViewModel
    let activityLogViewModel: ActivityLogViewModel
    let trashViewModel: TrashViewModel

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
        let activityContainer = try Self.makeActivityContainer()
        let (trashContainer, trashCacheURL) = try Self.makeTrashContainer()
        let autoTagContainer = try Self.makeAutoTagContainer()
        let checkpointContainer = try Self.makeCheckpointContainer()
        let checkpointStore = CheckpointStore(modelContainer: checkpointContainer)
        // Codex blocker #3: write to the shared keychain access group
        // so the File Provider extension (which reads from the same
        // group) can load credentials. Production-signed builds need
        // the entitlement provisioned at developer.apple.com — local
        // unsigned debug builds silently fall back to the private
        // namespace, which is harmless for development.
        //
        // On first launch with the shared-group code path, copy any
        // legacy private-namespace entries forward so the user's
        // existing accounts keep working — see `KeychainStore.migrateToSharedAccessGroupIfNeeded`.
        let keychainStore = KeychainStore(
            service: AppEnvironment.keychainService,
            accessGroup: AppEnvironment.keychainAccessGroup
        )
        Task { @MainActor [keychainStore] in
            await keychainStore.migrateFromLegacyPrivateNamespace()
        }
        let accountStore = AccountStore(modelContainer: modelContainer)
        let clientFactory = S3ClientFactory(keychainStore: keychainStore)
        let azureCredentialsCache = AzureCredentialsCache(keychainStore: keychainStore)
        let azureObjectStore = AzureBlobObjectStore(credentialsCache: azureCredentialsCache)
        // Phase 13.2 — one shared bandwidth limiter is hot-plugged
        // into both the Azure transporter and the TransferManager so
        // the cap counts every byte across providers.
        let bandwidthLimiter = BandwidthLimiter()
        let azureTransporter = AzureBlobTransporter(
            credentialsCache: azureCredentialsCache,
            limiter: bandwidthLimiter
        )
        let s3ObjectStore = S3Service(factory: clientFactory)
        let router = ProviderRouter(s3: s3ObjectStore, azure: azureObjectStore)
        let activityLog = ActivityLogStore(modelContainer: activityContainer)
        Task { [activityLog] in
            await activityLog.purgeExpired(retentionDays: 180)
        }
        let resumableUploader = S3ResumableUploader(
            factory: clientFactory,
            checkpointStore: checkpointStore
        )
        let transferManager = TransferManager(
            factory: clientFactory,
            azure: azureTransporter,
            activityLog: activityLog,
            limiter: bandwidthLimiter,
            resumableUploader: resumableUploader
        )
        let previewCache = PreviewCache(
            downloader: PreviewDownloader(
                s3Factory: clientFactory,
                azureTransporter: azureTransporter
            )
        )

        self.modelContainer = modelContainer
        self.activityContainer = activityContainer
        self.trashContainer = trashContainer
        self.autoTagContainer = autoTagContainer
        self.checkpointContainer = checkpointContainer
        self.checkpointStore = checkpointStore
        self.bandwidthLimiter = bandwidthLimiter
        self.bandwidthSettings = BandwidthSettings(limiter: bandwidthLimiter)
        self.keychainStore = keychainStore
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        self.azureCredentialsCache = azureCredentialsCache
        self.azureTransporter = azureTransporter
        self.s3Browser = router
        self.transferManager = transferManager
        self.previewCache = previewCache
        self.activityLog = activityLog
        self.accountListViewModel = AccountListViewModel(
            accountStore: accountStore,
            keychainStore: keychainStore,
            clientFactory: clientFactory,
            azureCredentialsCache: azureCredentialsCache,
            transferManager: transferManager,
            activityLog: activityLog
        )
        self.browserViewModel = BrowserViewModel(
            s3Browser: router,
            accountStore: accountStore,
            activityLog: activityLog
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
        let entitlementManager = EntitlementManager()
        self.entitlementManager = entitlementManager
        Task { @MainActor [entitlementManager] in
            await entitlementManager.bootstrap()
        }
        let syncJobStore = SyncJobStore(modelContainer: modelContainer)
        let syncEngine = SyncEngine(
            accountStore: accountStore,
            jobStore: syncJobStore,
            browser: router,
            transferManager: transferManager,
            activityLog: activityLog
        )
        self.syncJobStore = syncJobStore
        self.syncEngine = syncEngine
        self.syncJobListViewModel = SyncJobListViewModel(
            jobStore: syncJobStore,
            engine: syncEngine,
            accountStore: accountStore
        )
        self.activityLogViewModel = ActivityLogViewModel(
            activityLog: activityLog,
            accountStore: accountStore
        )
        let trashStore = TrashStore(
            modelContainer: trashContainer,
            cacheRootURL: trashCacheURL
        )
        let trashSettings = TrashSettings()
        let trashCoordinator = TrashCoordinator(
            trashStore: trashStore,
            browser: router,
            transferManager: transferManager,
            activityLog: activityLog,
            cacheRootURL: trashCacheURL,
            settings: trashSettings
        )
        self.trashStore = trashStore
        self.trashCoordinator = trashCoordinator
        self.trashSettings = trashSettings
        self.trashViewModel = TrashViewModel(
            trashStore: trashStore,
            coordinator: trashCoordinator,
            accountStore: accountStore
        )
        // Hand the trash coordinator to the browser so the inline
        // delete path can capture a soft-delete entry first.
        self.browserViewModel.trashCoordinator = trashCoordinator
        Task { [trashStore] in await trashStore.purgeExpired() }

        // Phase 13.8 — auto-tagging.
        let autoTagStore = AutoTagRuleStore(modelContainer: autoTagContainer)
        let autoTagCoordinator = AutoTagCoordinator(
            store: autoTagStore,
            browser: router,
            transferManager: transferManager,
            activityLog: activityLog,
            accountStore: accountStore
        )
        self.autoTagStore = autoTagStore
        self.autoTagCoordinator = autoTagCoordinator
        self.autoTagRulesViewModel = AutoTagRulesViewModel(
            store: autoTagStore,
            coordinator: autoTagCoordinator
        )
        Task { [autoTagCoordinator] in await autoTagCoordinator.start() }

        // Phase 13.11 — deep-link router. Holds a reference to the
        // browser so external bucketeer:// URLs land in the right
        // bucket and the AppleEvent handler can fire even when the
        // app is in `.accessory` (menu-bar) mode.
        self.deepLinkRouter = DeepLinkRouter(
            browser: self.browserViewModel,
            accountStore: accountStore
        )

        // Phase 13.13 — Spotlight indexer. Opt-in (default off).
        // Hooked into BrowserViewModel so every loaded page rolls
        // into the system index when the toggle is on.
        let spotlightSettings = SpotlightSettings()
        let spotlightIndexer = SpotlightIndexer(settings: spotlightSettings)
        self.spotlightSettings = spotlightSettings
        self.spotlightIndexer = spotlightIndexer
        self.browserViewModel.spotlightIndexer = spotlightIndexer

        // Phase 13.14 — cross-account copy / move.
        self.crossAccountCopyCoordinator = CrossAccountCopyCoordinator(
            browser: router,
            transferManager: transferManager,
            activityLog: activityLog
        )
        Task { @MainActor [syncJobListViewModel = self.syncJobListViewModel] in
            await syncJobListViewModel.bootstrap()
        }
        Task { @MainActor [activityLogViewModel = self.activityLogViewModel] in
            await activityLogViewModel.reload()
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

    /// Build the (host-only) activity log container. Phase 13.1. The
    /// activity store always lives in the sandbox Application Support
    /// folder — there's no reason to push it into the App Group.
    private static func makeActivityContainer() throws -> ModelContainer {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.documentsDirectory
        let storeURL = support.appending(path: AppEnvironment.activityStoreFileName)
        let schema = Schema([ActivityRecord.self])
        let configuration = ModelConfiguration(
            "BucketeerActivity",
            schema: schema,
            url: storeURL
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Phase 13.10 — host-only resumable-upload checkpoint container.
    private static func makeCheckpointContainer() throws -> ModelContainer {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.documentsDirectory
        let storeURL = support.appending(path: AppEnvironment.checkpointStoreFileName)
        let schema = Schema([MultipartUploadRecord.self])
        let configuration = ModelConfiguration(
            "BucketeerCheckpoints",
            schema: schema,
            url: storeURL
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Phase 13.8 — host-only auto-tagging rule container.
    private static func makeAutoTagContainer() throws -> ModelContainer {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.documentsDirectory
        let storeURL = support.appending(path: AppEnvironment.autoTagStoreFileName)
        let schema = Schema([AutoTagRuleRecord.self])
        let configuration = ModelConfiguration(
            "BucketeerAutoTags",
            schema: schema,
            url: storeURL
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Build the trash container + cache directory. Phase 13.4.
    /// Returns both because the `TrashStore` actor needs the cache
    /// directory URL alongside the model container.
    private static func makeTrashContainer() throws -> (ModelContainer, URL) {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.documentsDirectory
        let storeURL = support.appending(path: AppEnvironment.trashStoreFileName)
        let cacheURL = support.appending(path: AppEnvironment.trashCacheDirectoryName)
        try? FileManager.default.createDirectory(
            at: cacheURL,
            withIntermediateDirectories: true
        )
        let schema = Schema([TrashRecord.self])
        let configuration = ModelConfiguration(
            "BucketeerTrash",
            schema: schema,
            url: storeURL
        )
        let container = try ModelContainer(for: schema, configurations: configuration)
        return (container, cacheURL)
    }
}
