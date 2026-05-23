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
    let accountListViewModel: AccountListViewModel
    let browserViewModel: BrowserViewModel
    let transferQueueViewModel: TransferQueueViewModel

    init() throws {
        let storeURL = Self.resolveStoreURL()
        let schema = Schema([S3AccountRecord.self])
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

    /// Resolve the SwiftData store URL. Phase 2 always uses the sandbox
    /// Application Support directory so the location is stable across
    /// builds. Phase 9 introduces the App Group container alongside a
    /// one-shot migration that copies this store into the group
    /// container — that migration runs in the host app the first time
    /// the new entitlement is present.
    private static func resolveStoreURL() -> URL {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.documentsDirectory
        return support.appending(path: AppEnvironment.swiftDataStoreFileName)
    }
}
