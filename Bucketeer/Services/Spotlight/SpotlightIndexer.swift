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
/// Storage:
/// - Domain identifier: `za.co.digitalfreedom.bucketeer.spotlight`
/// - Each item's `uniqueIdentifier` is the `bucketeer://object/…`
///   deep link, so when the user clicks a Spotlight result the
///   `NSUserActivity` Apple hands us already carries the URL —
///   `DeepLinkRouter` routes it the same way as an external `open`.
@MainActor
final class SpotlightIndexer {
    private let index: CSSearchableIndex
    private let domainID: String
    private let settings: SpotlightSettings

    init(domainID: String = "za.co.digitalfreedom.bucketeer.spotlight",
         settings: SpotlightSettings) {
        self.index = CSSearchableIndex(name: domainID)
        self.domainID = domainID
        self.settings = settings
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
                domainIdentifier: domainID,
                attributeSet: attributes
            )
        }
        guard !items.isEmpty else { return }
        try? await index.indexSearchableItems(items)
    }

    /// Remove every indexed item for the given account. Called from
    /// `AccountListViewModel.delete` so removed accounts don't leave
    /// stale Spotlight hits.
    func purge(accountID: UUID) async {
        // Spotlight has no "filter by attribute" API at the
        // CSSearchableIndex level — the cleanest cross-version
        // approach is to nuke the whole domain and let the next
        // page-load rebuild it for remaining accounts.
        try? await index.deleteSearchableItems(withDomainIdentifiers: [domainID])
    }

    /// Wipe the entire Bucketeer Spotlight domain. Called from the
    /// Settings toggle when the user turns indexing off.
    func purgeAll() async {
        try? await index.deleteSearchableItems(withDomainIdentifiers: [domainID])
    }
}
