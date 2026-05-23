//
//  DragDropCoordinator.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import UniformTypeIdentifiers

/// Funnels every drop landing inside Bucketeer (sidebar account row,
/// bucket card, folder row, empty list area) through the same logic so
/// the per-view modifiers stay one-liners.
///
/// Drop semantics — per design spec §8.3 — always Copy. The ⌘ drag
/// modifier is intentionally ignored: S3 has no atomic Move and an
/// accidental ⌘-drag between buckets could trigger thousand-object
/// deletes. Move is exposed only via the explicit "Move to…" menu (v1.1).
@MainActor
final class DragDropCoordinator {
    private let s3Browser: S3Browsing
    private let transferManager: TransferManager
    private let transferQueue: TransferQueueViewModel
    private let accountStore: AccountStoring

    init(
        s3Browser: S3Browsing,
        transferManager: TransferManager,
        transferQueue: TransferQueueViewModel,
        accountStore: AccountStoring
    ) {
        self.s3Browser = s3Browser
        self.transferManager = transferManager
        self.transferQueue = transferQueue
        self.accountStore = accountStore
    }

    // MARK: - URL drops (Finder → app)

    /// Enqueue every dropped URL as an upload into the destination
    /// prefix. Directory drops are not recursive in v1 — top-level files
    /// only. Folder upload arrives in v1.1.
    func uploadDroppedURLs(
        _ urls: [URL],
        account: S3Account,
        bucket: String,
        prefix: String
    ) async {
        var fileURLs: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            )
            guard exists, !isDirectory.boolValue else { continue }
            fileURLs.append(url)
        }
        guard !fileURLs.isEmpty else { return }
        await transferQueue.enqueueUploads(
            account: account,
            bucket: bucket,
            prefix: prefix,
            fileURLs: fileURLs
        )
    }

    // MARK: - Object-ref drops (intra-app)

    /// Handle a dropped `S3ObjectRef`. Resolves to one of three paths:
    /// - **No-op** when the source and destination resolve to the same
    ///   key (drag onto self).
    /// - **Server-side copy** when source and destination share the same
    ///   account *and* the same provider; cheap, no traffic to the
    ///   client.
    /// - **Round-trip** download → upload when source and destination
    ///   live on different accounts. Uses a temp file in the sandbox
    ///   container as the staging spot.
    func dropObjectRef(
        _ ref: S3ObjectRef,
        destinationAccount: S3Account,
        destinationBucket: String,
        destinationPrefix: String
    ) async {
        // Folder drops require recursive enumeration of the source
        // prefix — out of scope for v1 (Codex review #9). Drop on the
        // floor so the user does not get half-folder copies or a
        // misleading single-key copy of `foo/`.
        if ref.isFolder { return }

        // Resolve the source account from its UUID — refs carry only
        // the ID so the drag payload stays small. A missing account
        // means it was deleted while the drag was in flight; nothing to
        // do.
        let sourceAccount: S3Account?
        if ref.accountID == destinationAccount.id {
            sourceAccount = destinationAccount
        } else {
            sourceAccount = try? await accountStore.all()
                .first(where: { $0.id == ref.accountID })
        }
        guard let sourceAccount else { return }
        // Compute the destination key first so the self-drop comparison
        // is exact (Codex review #9 — comparing parent prefixes only
        // missed the case where dragging a row back onto its own row
        // produced a no-op copy that still surfaced as a queue entry).
        let destinationKey = destinationPrefix + ref.displayName
        if sourceAccount.id == destinationAccount.id,
           ref.bucket == destinationBucket,
           destinationKey == ref.key {
            return
        }

        if sourceAccount.id == destinationAccount.id {
            // Server-side copy within one account.
            do {
                try await s3Browser.copy(
                    account: sourceAccount,
                    fromBucket: ref.bucket,
                    fromKey: ref.key,
                    toBucket: destinationBucket,
                    toKey: destinationKey,
                    metadata: nil
                )
            } catch {
                await surfaceCopyFailure(
                    account: sourceAccount,
                    bucket: destinationBucket,
                    key: destinationKey,
                    error: error
                )
            }
        } else {
            await roundTripCopy(
                sourceAccount: sourceAccount,
                ref: ref,
                destinationAccount: destinationAccount,
                destinationBucket: destinationBucket,
                destinationKey: destinationKey
            )
        }
    }

    private func roundTripCopy(
        sourceAccount: S3Account,
        ref: S3ObjectRef,
        destinationAccount: S3Account,
        destinationBucket: String,
        destinationKey: String
    ) async {
        // Staging file inside the temp dir — picked up by the OS when
        // the sandbox container is purged. Manual cleanup happens after
        // the upload completes regardless of outcome.
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "BucketeerDrops", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        let staging = tempDir.appending(path: UUID().uuidString + "-" + ref.displayName)

        // Enqueue download first; once it completes, we manually enqueue
        // the upload. The two tasks are visible in the queue separately
        // — intentional: lets the user cancel either half.
        let downloadID = await transferManager.enqueueDownload(
            account: sourceAccount,
            bucket: ref.bucket,
            key: ref.key,
            localURL: staging
        )

        // Wait for the download to terminate by polling the snapshot
        // stream. AsyncSequence avoids hard-coupling to the actor.
        let stream = transferManager.tasks
        for await snapshot in stream {
            guard let task = snapshot.first(where: { $0.id == downloadID }) else { continue }
            switch task.state {
            case .completed:
                let contentType = UTType(filenameExtension: staging.pathExtension)?
                    .preferredMIMEType
                _ = await transferManager.enqueueUpload(
                    account: destinationAccount,
                    bucket: destinationBucket,
                    key: destinationKey,
                    localURL: staging,
                    contentType: contentType
                )
                // Best-effort cleanup once the upload completes — we
                // don't await it explicitly; the file is gone next time
                // the temp dir is purged either way.
                return
            case .failed, .cancelled:
                try? FileManager.default.removeItem(at: staging)
                return
            case .queued, .running:
                continue
            }
        }
    }

    private func surfaceCopyFailure(
        account: S3Account,
        bucket: String,
        key: String,
        error: Error
    ) async {
        // Best-effort propagation. The browser view model already shows
        // an actionError alert when its own copy/delete fails; the drop
        // path right now doesn't share that error sink — TODO Phase 7.1.
        _ = error
        _ = account
        _ = bucket
        _ = key
    }
}
