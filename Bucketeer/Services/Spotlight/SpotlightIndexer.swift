//
//  SpotlightIndexer.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import BucketeerCore

/// Pushes browsed-object metadata into macOS Spotlight so the user
/// can find their cloud files from the system search. Phase 13.13.
///
/// Privacy posture: indexing is **opt-in**. The Settings toggle
/// (`SpotlightSettings.enabled`) defaults to `false` — turning it on
/// states intent to make object keys browsable system-wide. The
/// indexer never indexes object contents, only filenames + bucket /
/// account context.
///
/// Domain layout (Codex audit R2 low + R3 high #3 follow-ups):
/// - Base domain: `za.co.digitalfreedom.bucketeer.spotlight`
/// - Per-account sub-domain:
///   `za.co.digitalfreedom.bucketeer.spotlight.<accountUUID>`
///
/// Items live under their account's sub-domain so
/// `purgeAccount(_:)` can wipe one account without touching the
/// rest. `CSSearchableIndex.deleteSearchableItems(withDomainIdentifiers:)`
/// matches by **exact** domain string (not prefix — Codex R3
/// caught the wrong assumption), so `purgeAll()` iterates every
/// sub-domain we've ever indexed plus the base domain.
///
/// The set of indexed-account UUIDs is mirrored to `UserDefaults`
/// under `spotlight.indexed.accounts` so the iteration survives an
/// app relaunch.
@MainActor
final class SpotlightIndexer {
    private let index: CSSearchableIndex
    private let domainID: String
    private let settings: SpotlightSettings
    private let defaults: UserDefaults
    private static let indexedAccountsKey = "spotlight.indexed.accounts"

    init(domainID: String = "za.co.digitalfreedom.bucketeer.spotlight",
         settings: SpotlightSettings,
         defaults: UserDefaults = .standard) {
        self.index = CSSearchableIndex(name: domainID)
        self.domainID = domainID
        self.settings = settings
        self.defaults = defaults
    }

    /// Add or refresh a page of objects in the index. No-op when
    /// indexing is disabled. Folders are skipped — they have no
    /// "open" semantics through a deep link.
    func indexPage(
        account: S3Account,
        bucket: String,
        objects: [S3Object]
    ) async {
        guard settings.enabled else { return }
        let accountDomain = Self.domain(for: account.id, baseDomain: domainID)
        let items: [CSSearchableItem] = objects.compactMap { object -> CSSearchableItem? in
            guard !object.isFolder else { return nil }
            let link = BucketeerDeepLink.object(
                accountID: account.id,
                bucket: bucket,
                key: object.key
            )
            guard let url = link.url else { return nil }
            let attributes = CSSearchableItemAttributeSet(itemContentType: UTType.item.identifier)
            attributes.title = object.displayName
            attributes.displayName = object.displayName
            attributes.contentDescription = "\(account.name) · \(bucket)/\(object.key)"
            attributes.containerTitle = bucket
            attributes.containerDisplayName = account.name
            attributes.fileSize = NSNumber(value: object.size)
            attributes.contentModificationDate = object.lastModified
            return CSSearchableItem(
                uniqueIdentifier: url.absoluteString,
                domainIdentifier: accountDomain,
                attributeSet: attributes
            )
        }
        guard !items.isEmpty else { return }
        try? await index.indexSearchableItems(items)
        rememberAccountDomain(account.id)
    }

    /// Wipe every Bucketeer Spotlight entry. Codex R3 (high #3):
    /// CSSearchableIndex domain-match is exact, so we explicitly
    /// iterate every sub-domain we've ever touched plus the base
    /// domain (legacy items indexed before the sub-domain layout
    /// landed).
    ///
    /// Codex R4 (high): only clear the tracking set after the
    /// delete actually succeeds. A failed delete that still
    /// emptied the tracking set would leave stale Spotlight items
    /// with no way to target them on a re-attempt.
    func purgeAll() async {
        var domains = trackedAccountDomains()
        domains.append(domainID)
        do {
            try await index.deleteSearchableItems(withDomainIdentifiers: domains)
            defaults.removeObject(forKey: Self.indexedAccountsKey)
        } catch {
            // Leave the tracking set intact — a subsequent purgeAll
            // will retry the same domain list.
        }
    }

    /// Remove every indexed item for the given account. Targets only
    /// the account's sub-domain, so the other accounts' items stay
    /// searchable. Codex audit R2 (low) follow-up.
    ///
    /// Codex R4 (high): same retry-friendliness as `purgeAll` —
    /// the tracking entry only goes away after Spotlight confirms
    /// the delete.
    func purgeAccount(_ accountID: UUID) async {
        let target = Self.domain(for: accountID, baseDomain: domainID)
        do {
            try await index.deleteSearchableItems(withDomainIdentifiers: [target])
            forgetAccountDomain(accountID)
        } catch {
            // Tracking set stays; the next purge attempt re-tries.
        }
    }

    /// Stable per-account sub-domain. Lower-cased so a round-trip
    /// through Apple's APIs (which sometimes lower-case identifiers)
    /// is byte-stable.
    static func domain(for accountID: UUID, baseDomain: String) -> String {
        "\(baseDomain).\(accountID.uuidString.lowercased())"
    }

    // MARK: - UserDefaults-backed account tracking

    private func trackedAccountDomains() -> [String] {
        let ids = (defaults.array(forKey: Self.indexedAccountsKey) as? [String]) ?? []
        return ids.compactMap { idString in
            guard let uuid = UUID(uuidString: idString) else { return nil }
            return Self.domain(for: uuid, baseDomain: domainID)
        }
    }

    private func rememberAccountDomain(_ accountID: UUID) {
        var ids = Set((defaults.array(forKey: Self.indexedAccountsKey) as? [String]) ?? [])
        ids.insert(accountID.uuidString.lowercased())
        defaults.set(Array(ids), forKey: Self.indexedAccountsKey)
    }

    private func forgetAccountDomain(_ accountID: UUID) {
        var ids = Set((defaults.array(forKey: Self.indexedAccountsKey) as? [String]) ?? [])
        ids.remove(accountID.uuidString.lowercased())
        defaults.set(Array(ids), forKey: Self.indexedAccountsKey)
    }
}
