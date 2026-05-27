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

    init() {}

    /// Refresh the cached list from the system. Idempotent.
    func refresh() async {
        do {
            let domains = try await NSFileProviderManager.domains()
            mountedDomains = domains.map(\.identifier)
        } catch {
            lastError = .unknown(message: error.localizedDescription)
        }
    }

    /// Add a `NSFileProviderDomain` for the given bucket. No-op when
    /// the domain is already registered.
    func mount(account: S3Account, bucket: String) async {
        let identifier = Self.domainIdentifier(accountID: account.id, bucket: bucket)
        let domain = NSFileProviderDomain(
            identifier: identifier,
            displayName: "\(account.name): \(bucket)"
        )
        do {
            try await NSFileProviderManager.add(domain)
            await refresh()
        } catch {
            lastError = mapMountError(error)
        }
    }

    /// Remove a previously-mounted bucket. No-op when no domain matches.
    func unmount(account: S3Account, bucket: String) async {
        let identifier = Self.domainIdentifier(accountID: account.id, bucket: bucket)
        do {
            let domains = try await NSFileProviderManager.domains()
            if let domain = domains.first(where: { $0.identifier == identifier }) {
                try await NSFileProviderManager.remove(domain)
            }
            await refresh()
        } catch {
            lastError = mapMountError(error)
        }
    }

    /// Tear down every mounted domain — used when the host app uninstalls
    /// (Phase 12) or the user clears all data via Settings.
    func unmountAll() async {
        do {
            let domains = try await NSFileProviderManager.domains()
            for domain in domains {
                try await NSFileProviderManager.remove(domain)
            }
            await refresh()
        } catch {
            lastError = mapMountError(error)
        }
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
