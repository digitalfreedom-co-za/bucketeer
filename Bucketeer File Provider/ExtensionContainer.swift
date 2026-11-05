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
/// - The SwiftData store in the App Group container — opened with the
///   host's schema and `allowsSave: false`
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
    let encryptedBucketListURL: URL

    init() throws {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppEnvironment.appGroupIdentifier
        ) else {
            throw NSError(
                domain: "BucketeerFileProvider",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "App Group container is not available — entitlement missing or not yet provisioned."]
            )
        }
        self.encryptedBucketListURL = EncryptedBucketList.url(inGroupContainer: groupURL)
        let storeURL = groupURL.appending(path: AppEnvironment.swiftDataStoreFileName)
        // Same schema as the host (never a subset — that would migrate
        // away the host's sync jobs); saves are disabled here.
        self.modelContainer = try SharedStore.makeContainer(url: storeURL, allowsSave: false)
        let keychain = KeychainStore(
            service: AppEnvironment.keychainService,
            accessGroup: AppEnvironment.keychainAccessGroup
        )
        self.keychainStore = keychain
        self.accountStore = AccountStore(modelContainer: self.modelContainer)
        // The host bumps the revision when an account changes, so these
        // caches drop credentials edited in the app.
        let factory = S3ClientFactory(keychainStore: keychain, revision: .appGroup)
        self.clientFactory = factory
        let azureCache = AzureCredentialsCache(keychainStore: keychain, revision: .appGroup)
        self.azureCredentialsCache = azureCache
        let azureStore = AzureBlobObjectStore(credentialsCache: azureCache)
        self.azureTransporter = AzureBlobTransporter(credentialsCache: azureCache)
        let s3Store = S3Service(factory: factory)
        self.browser = ProviderRouter(s3: s3Store, azure: azureStore)
    }

    /// Refuses moving bytes for a bucket with client-side encryption:
    /// this extension reads and writes raw bytes, so Finder would see
    /// ciphertext and upload plaintext. Fails closed when the host's
    /// encrypted-bucket list is missing or unreadable.
    func refuseIfEncrypted(_ identifier: String) throws {
        let isEncrypted = (try? EncryptedBucketList.contains(
            domainIdentifier: identifier,
            at: encryptedBucketListURL
        )) ?? true
        guard isEncrypted else { return }
        throw NSError(
            domain: NSCocoaErrorDomain,
            code: NSFeatureUnsupportedError,
            userInfo: [NSLocalizedDescriptionKey: "This bucket uses client-side encryption and can't be used in Finder. Open it in the Bucketeer window instead."]
        )
    }

    /// Refuses changing a mounted bucket once Bucketeer Pro has lapsed.
    /// The mount stays and reads keep working; unmounting would drop
    /// Finder changes not uploaded yet.
    func refuseIfReadOnly() throws {
        guard FinderWriteAccess.appGroup.isReadOnly else { return }
        throw NSError(
            domain: NSCocoaErrorDomain,
            code: NSFeatureUnsupportedError,
            userInfo: [NSLocalizedDescriptionKey: "Changing files of a mounted bucket in Finder needs Bucketeer Pro. The files stay readable; open Bucketeer to unlock Pro."]
        )
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
