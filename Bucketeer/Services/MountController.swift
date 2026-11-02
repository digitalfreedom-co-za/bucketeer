//
//  MountController.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import FileProvider
import BucketeerCore

/// Manages the File Provider domains that expose mounted buckets in
/// Finder under Locations. One `NSFileProviderDomain` per mounted
/// bucket, identifier `"<accountID.uuidString>::<bucket>"` so the
/// extension can resolve the corresponding account from the shared
/// SwiftData store.
///
/// **Provisioning:** requires the App Group entitlement
/// `group.za.co.digitalfreedom.bucketeer` and the shared Keychain
/// access group on both the host app and the File Provider extension
/// target. Until those are provisioned at developer.apple.com and the
/// extension target is added in Xcode, mount calls fail with
/// `NSFileProviderError.providerNotFound` and the UI surfaces the
/// error gracefully.
@MainActor
@Observable
final class MountController {
    /// Live list of mounted domains, keyed by their identifier string.
    /// Refreshed from `NSFileProviderManager` on demand.
    var mountedDomains: [NSFileProviderDomainIdentifier] = []
    var lastError: BucketeerError?

    /// The File Provider extension's deployment target is macOS 14.1
    /// while the host runs on 14.0, so Mount is unavailable on 14.0.
    static var isSupportedOnThisSystem: Bool {
        if #available(macOS 14.1, *) { return true }
        return false
    }

    private let encryptionKeyStore: any EncryptionKeyStoring
    private let registry: any FileProviderDomainRegistry
    /// Buckets with a mount or an encryption change in flight. Both
    /// flows reserve the bucket before their first check and release
    /// it after their last await, so neither can act on a state the
    /// other is about to change.
    private var bucketsInFlight: Set<NSFileProviderDomainIdentifier> = []

    init(
        encryptionKeyStore: any EncryptionKeyStoring,
        registry: any FileProviderDomainRegistry = SystemFileProviderDomainRegistry()
    ) {
        self.encryptionKeyStore = encryptionKeyStore
        self.registry = registry
    }

    /// Refresh the cached list from the system. Idempotent.
    func refresh() async {
        do {
            mountedDomains = try await registry.identifiers()
        } catch {
            lastError = .unknown(message: error.localizedDescription)
        }
    }

    /// Add a `NSFileProviderDomain` for the given bucket. No-op when
    /// the domain is already registered.
    ///
    /// Refuses encrypted buckets: the extension reads and writes raw
    /// bytes, so Finder uploads would bypass client-side encryption.
    /// A failed key lookup also refuses (fail closed).
    func mount(account: S3Account, bucket: String) async {
        guard Self.isSupportedOnThisSystem else {
            lastError = .unknown(message: String(
                localized: "mount.error.requiresNewerMacOS",
                defaultValue: "Mounting buckets in Finder requires macOS 14.1 or later."
            ))
            return
        }
        let identifier = Self.domainIdentifier(accountID: account.id, bucket: bucket)
        guard reserve(identifier) else {
            lastError = Self.busyError
            return
        }
        defer { bucketsInFlight.remove(identifier) }
        let isEncrypted: Bool
        do {
            isEncrypted = try await encryptionKeyStore.key(accountID: account.id, bucket: bucket) != nil
        } catch {
            lastError = error as? BucketeerError ?? .unknown(message: error.localizedDescription)
            return
        }
        guard !isEncrypted else {
            lastError = .unknown(message: String(
                localized: "mount.error.encryptedBucket",
                defaultValue: "This bucket uses client-side encryption. Encrypted buckets can't be mounted in Finder yet; transfer its files in the Bucketeer window instead."
            ))
            return
        }
        do {
            try await registry.add(identifier: identifier, displayName: "\(account.name): \(bucket)")
            await refresh()
        } catch {
            lastError = mapMountError(error)
        }
    }

    /// Remove a previously-mounted bucket. No-op when no domain matches.
    func unmount(account: S3Account, bucket: String) async {
        let identifier = Self.domainIdentifier(accountID: account.id, bucket: bucket)
        do {
            try await registry.remove(identifier: identifier)
            await refresh()
        } catch {
            lastError = mapMountError(error)
        }
    }

    /// Runs `operation` (turning on encryption) only after a fresh
    /// domain lookup succeeded and showed the bucket is not mounted,
    /// and keeps mounts of the bucket out until it returns. A failed
    /// lookup throws instead of assuming "not mounted".
    func whileUnmounted(
        account: S3Account,
        bucket: String,
        _ operation: () async throws -> Void
    ) async throws {
        let identifier = Self.domainIdentifier(accountID: account.id, bucket: bucket)
        guard reserve(identifier) else { throw Self.busyError }
        defer { bucketsInFlight.remove(identifier) }
        do {
            mountedDomains = try await registry.identifiers()
        } catch {
            throw BucketeerError.unknown(message: String(
                localized: "encryption.error.mountStateUnknown",
                defaultValue: "Bucketeer couldn't check whether this bucket is mounted in Finder, so encryption stays off. Try again."
            ))
        }
        guard !mountedDomains.contains(identifier) else {
            throw BucketeerError.unknown(message: String(
                localized: "encryption.error.bucketMounted",
                defaultValue: "This bucket is mounted in Finder. Unmount it before turning on encryption, because files copied through Finder would not be encrypted."
            ))
        }
        try await operation()
    }

    private func reserve(_ identifier: NSFileProviderDomainIdentifier) -> Bool {
        bucketsInFlight.insert(identifier).inserted
    }

    private static var busyError: BucketeerError {
        .unknown(message: String(
            localized: "mount.error.busy",
            defaultValue: "Another change to this bucket is still running. Try again in a moment."
        ))
    }

    func isMounted(account: S3Account, bucket: String) -> Bool {
        let identifier = Self.domainIdentifier(accountID: account.id, bucket: bucket)
        return mountedDomains.contains(identifier)
    }

    static func domainIdentifier(accountID: UUID, bucket: String) -> NSFileProviderDomainIdentifier {
        NSFileProviderDomainIdentifier(rawValue: "\(accountID.uuidString)::\(bucket)")
    }

    /// Parse the colon-separated identifier the extension hands us on
    /// `init(domain:)`.
    static func parse(_ identifier: NSFileProviderDomainIdentifier) -> (accountID: UUID, bucket: String)? {
        let raw = identifier.rawValue
        guard let separatorRange = raw.range(of: "::") else { return nil }
        let idPart = String(raw[..<separatorRange.lowerBound])
        let bucket = String(raw[separatorRange.upperBound...])
        guard let uuid = UUID(uuidString: idPart) else { return nil }
        return (uuid, bucket)
    }

    private func mapMountError(_ error: Error) -> BucketeerError {
        let nsError = error as NSError
        if nsError.domain == NSFileProviderErrorDomain {
            if nsError.code == NSFileProviderError.providerNotFound.rawValue {
                return .unknown(message: String(
                    localized: "mount.error.notProvisioned",
                    defaultValue: "The File Provider extension is not yet provisioned. App Group entitlement and the extension target must be set up first."
                ))
            }
            if #available(macOS 14.1, *),
               nsError.code == NSFileProviderError.providerDomainNotFound.rawValue {
                return .unknown(message: String(
                    localized: "mount.error.notFound",
                    defaultValue: "That mounted bucket no longer exists."
                ))
            }
        }
        return .unknown(message: error.localizedDescription)
    }
}
