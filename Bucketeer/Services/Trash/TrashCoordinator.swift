//
//  TrashCoordinator.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import BucketeerCore

/// Bridges the soft-delete trash to the rest of the host services
/// (browser, transfer manager, activity log) so the `TrashStore`
/// actor stays focused on persistence. Phase 13.4.
///
/// The coordinator does three things:
///
/// 1. **Capture** — `recordDeletion(...)` is called by the browser
///    *before* the provider delete. It HEADs each key, persists a
///    `TrashedItem`, and (if caching is enabled and the file fits)
///    kicks off a background download into the local trash cache.
/// 2. **Restore** — re-uploads the cached payload via the existing
///    `TransferManager` to the original bucket+key. On success the
///    record is forgotten.
/// 3. **Forget / Empty** — simple pass-throughs that delegate to the
///    store so the cached file is removed in lockstep.
@MainActor
final class TrashCoordinator {
    private let trashStore: any TrashStoring
    private let browser: any S3Browsing
    private let transferManager: TransferManager
    private let activityLog: any ActivityLogging
    private let cacheRootURL: URL
    private let settings: TrashSettings

    init(
        trashStore: any TrashStoring,
        browser: any S3Browsing,
        transferManager: TransferManager,
        activityLog: any ActivityLogging,
        cacheRootURL: URL,
        settings: TrashSettings
    ) {
        self.trashStore = trashStore
        self.browser = browser
        self.transferManager = transferManager
        self.activityLog = activityLog
        self.cacheRootURL = cacheRootURL
        self.settings = settings
    }

    /// Snapshot every key the user is about to delete, record a
    /// `TrashedItem` for each, and synchronously download cacheable
    /// payloads into the local trash directory.
    ///
    /// Returns only after every cache attempt has finished. The
    /// caller (`BrowserViewModel.delete`) MUST invoke this **before**
    /// the actual provider delete — that way the object is still
    /// readable when we GET it and the cached copy is guaranteed to
    /// be the pre-delete bytes.
    func recordDeletion(
        account: S3Account,
        bucket: String,
        keys: [String]
    ) async {
        guard !keys.isEmpty else { return }
        let now = Date()
        let expires = now.addingTimeInterval(
            Double(settings.retentionDays) * 24 * 60 * 60
        )
        let cacheEnabled = settings.cacheEnabled
        let cacheCapBytes = settings.cacheCapBytes

        struct CacheTarget: Sendable {
            let id: UUID
            let key: String
        }
        var pendingCaches: [CacheTarget] = []

        for key in keys {
            let head = try? await browser.head(account: account, bucket: bucket, key: key)
            let size = head?.size ?? 0
            let cacheStatus: TrashCacheStatus = {
                guard cacheEnabled else { return .skippedDisabled }
                guard size > 0 else { return .skippedDisabled }
                return size <= cacheCapBytes ? .pending : .skippedTooLarge
            }()
            let item = TrashedItem(
                accountID: account.id,
                accountName: account.name,
                bucket: bucket,
                key: key,
                size: size,
                contentType: head?.contentType,
                etag: head?.etag,
                deletedAt: now,
                expiresAt: expires,
                cacheStatus: cacheStatus
            )
            await trashStore.record(item)
            if cacheStatus == .pending {
                pendingCaches.append(CacheTarget(id: item.id, key: key))
            }
        }

        // Cache eligible payloads in parallel so the user's delete
        // doesn't sit idle while N small files download sequentially.
        // The TransferManager already caps concurrency.
        await withTaskGroup(of: Void.self) { group in
            for target in pendingCaches {
                group.addTask { [weak self] in
                    await self?.captureCachedPayload(
                        for: target.id,
                        account: account,
                        bucket: bucket,
                        key: target.key
                    )
                }
            }
        }
    }

    /// Download the about-to-be-deleted object into the local trash
    /// cache. Always called BEFORE the provider delete via
    /// `recordDeletion`, so the read is guaranteed.
    private func captureCachedPayload(
        for id: UUID,
        account: S3Account,
        bucket: String,
        key: String
    ) async {
        let fileName = id.uuidString + ".bin"
        let destURL = cacheRootURL.appendingPathComponent(fileName)
        // Codex audit fix (high #2): the trash cache must keep the
        // raw bytes as the object exists on the provider — for an
        // encrypted bucket that's the Bucketeer envelope, not
        // plaintext. Without `bypassDecryption: true`, the local
        // cache would hold a plaintext copy of every encrypted
        // object the user ever deleted.
        let downloadID = await transferManager.enqueueDownload(
            account: account,
            bucket: bucket,
            key: key,
            localURL: destURL,
            bypassDecryption: true
        )
        let state = await transferManager.awaitCompletion(id: downloadID)
        switch state {
        case .completed:
            await trashStore.markCached(id: id, fileName: fileName)
        default:
            try? FileManager.default.removeItem(at: destURL)
            await trashStore.markStatus(id: id, status: .failed)
        }
    }

    /// Re-upload the cached payload to a destination chosen by the
    /// caller. Returns `nil` on success, an error message otherwise.
    func restore(
        item: TrashedItem,
        toBucket: String? = nil,
        toKey: String? = nil,
        account: S3Account
    ) async -> String? {
        guard let cachedName = item.cachedFileName,
              item.cacheStatus == .cached else {
            return String(
                localized: "trash.error.notRestorable",
                defaultValue: "This entry has no cached copy and cannot be restored."
            )
        }
        let fileURL = cacheRootURL.appendingPathComponent(cachedName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return String(
                localized: "trash.error.cacheMissing",
                defaultValue: "The cached file is gone from disk."
            )
        }
        let destinationBucket = toBucket ?? item.bucket
        let destinationKey = toKey ?? item.key
        let id = await transferManager.enqueueUpload(
            account: account,
            bucket: destinationBucket,
            key: destinationKey,
            localURL: fileURL,
            contentType: item.contentType
        )
        let state = await transferManager.awaitCompletion(id: id)
        switch state {
        case .completed:
            try? await trashStore.forget(id: item.id)
            return nil
        case .failed(let message):
            return message
        case .cancelled:
            return String(
                localized: "trash.error.restoreCancelled",
                defaultValue: "Restore was cancelled."
            )
        default:
            return String(
                localized: "trash.error.restoreUnknown",
                defaultValue: "Restore did not finish."
            )
        }
    }

    /// Forget = delete the record + cached file. The provider object
    /// has been gone since the delete.
    func forget(item: TrashedItem) async -> String? {
        do {
            try await trashStore.forget(id: item.id)
            return nil
        } catch let error as BucketeerError {
            return error.errorDescription
        } catch {
            return error.localizedDescription
        }
    }

    /// Empty = clean every record + every cached file.
    func empty() async -> String? {
        do {
            try await trashStore.empty()
            return nil
        } catch let error as BucketeerError {
            return error.errorDescription
        } catch {
            return error.localizedDescription
        }
    }
}
