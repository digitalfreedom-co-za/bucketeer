//
//  ExtensionContainer.swift
//  Bucketeer File Provider
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import SwiftData
import BucketeerCore

/// Minimal composition root for the File Provider extension. Mirrors the
/// services the host's `AppContainer` exposes but skips the UI-bound
/// pieces (TransferManager queue, ViewModels, EntitlementManager). All
/// shared services are pulled from `BucketeerCore`.
///
/// The extension shares two pieces of state with the host:
/// - The SwiftData store in the App Group container — read-only here
/// - The Keychain access group — per-account credentials
///
/// All stored properties are `let` and reference Sendable services or
/// the SwiftData container (which is internally synchronised); no
/// `@unchecked Sendable` escape hatch needed.
final class ExtensionContainer: Sendable {
    let modelContainer: ModelContainer
    let accountStore: any AccountStoring
    let keychainStore: any KeychainStoring
    let clientFactory: S3ClientFactory
    let azureCredentialsCache: AzureCredentialsCache
    let azureTransporter: AzureBlobTransporter
    let browser: any S3Browsing

    init() throws {
        let schema = Schema([S3AccountRecord.self])
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppEnvironment.appGroupIdentifier
        ) else {
            throw NSError(
                domain: "BucketeerFileProvider",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "App Group container is not available — entitlement missing or not yet provisioned."]
            )
        }
        let storeURL = groupURL.appending(path: AppEnvironment.swiftDataStoreFileName)
        let configuration = ModelConfiguration(
            "Bucketeer",
            schema: schema,
            url: storeURL
        )
        self.modelContainer = try ModelContainer(
            for: schema,
            configurations: configuration
        )
        let keychain = KeychainStore(
            service: AppEnvironment.keychainService,
            accessGroup: AppEnvironment.keychainAccessGroup
        )
        self.keychainStore = keychain
        self.accountStore = AccountStore(modelContainer: self.modelContainer)
        let factory = S3ClientFactory(keychainStore: keychain)
        self.clientFactory = factory
        let azureCache = AzureCredentialsCache(keychainStore: keychain)
        self.azureCredentialsCache = azureCache
        let azureStore = AzureBlobObjectStore(credentialsCache: azureCache)
        self.azureTransporter = AzureBlobTransporter(credentialsCache: azureCache)
        let s3Store = S3Service(factory: factory)
        self.browser = ProviderRouter(s3: s3Store, azure: azureStore)
    }

    /// Resolve the `(account, bucket)` tuple that a domain identifier
    /// encodes. Returns nil when the account no longer exists.
    func resolve(_ identifier: String) async throws -> (account: S3Account, bucket: String)? {
        guard let separatorRange = identifier.range(of: "::"),
              let uuid = UUID(uuidString: String(identifier[..<separatorRange.lowerBound]))
        else { return nil }
        let bucket = String(identifier[separatorRange.upperBound...])
        let accounts = try await accountStore.all()
        guard let account = accounts.first(where: { $0.id == uuid }) else { return nil }
        return (account, bucket)
    }
}
