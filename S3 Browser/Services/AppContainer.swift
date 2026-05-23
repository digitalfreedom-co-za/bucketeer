//
//  AppContainer.swift
//  S3 Browser
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
    let s3Browser: S3Browsing
    let transferManager: TransferManager
    let accountListViewModel: AccountListViewModel
    let browserViewModel: BrowserViewModel
    let transferQueueViewModel: TransferQueueViewModel

    init() throws {
        let storeURL = Self.resolveStoreURL()
        let schema = Schema([S3AccountRecord.self])
        let configuration = ModelConfiguration(
            "S3Browser",
            schema: schema,
            url: storeURL
        )
        let modelContainer = try ModelContainer(
            for: schema,
            configurations: configuration
        )
        let keychainStore = KeychainStore(
            service: AppEnvironment.keychainService,
            accessGroup: nil // Shared access group is added in Phase 9 with the File Provider extension.
        )
        let accountStore = AccountStore(modelContainer: modelContainer)
        let clientFactory = S3ClientFactory(keychainStore: keychainStore)
        let s3Browser = S3BrowserService(factory: clientFactory)
        let transferManager = TransferManager(factory: clientFactory)

        self.modelContainer = modelContainer
        self.keychainStore = keychainStore
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        self.s3Browser = s3Browser
        self.transferManager = transferManager
        self.accountListViewModel = AccountListViewModel(
            accountStore: accountStore,
            keychainStore: keychainStore,
            clientFactory: clientFactory,
            transferManager: transferManager
        )
        self.browserViewModel = BrowserViewModel(
            s3Browser: s3Browser,
            accountStore: accountStore
        )
        self.transferQueueViewModel = TransferQueueViewModel(
            transferManager: transferManager
        )
        self.transferQueueViewModel.startObserving()
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
