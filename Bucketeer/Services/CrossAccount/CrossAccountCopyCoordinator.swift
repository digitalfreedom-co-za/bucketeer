//
//  CrossAccountCopyCoordinator.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import BucketeerCore

/// Copy one or more objects from a source account/bucket to a
/// destination account/bucket. Phase 13.14.
///
/// Routing strategy, in order of preference:
///
/// 1. **Server-side `CopyObject`** when both accounts are on the
///    same provider family AND share the same endpoint. This is the
///    fastest path — no data crosses the user's network.
/// 2. **Local round-trip** otherwise — download to a sandboxed temp
///    file, upload to the destination, drop the temp.
///
/// The coordinator records one activity row per object so the user
/// can audit cross-account moves in the Activity window.
@MainActor
final class CrossAccountCopyCoordinator {
    private let browser: any S3Browsing
    private let transferManager: TransferManager
    private let activityLog: any ActivityLogging
    /// Optional encryption gate so we can detect "either side has a
    /// BYOK key" and force the round-trip rewrap path — Codex audit
    /// fix (high #1). Without it, server-side `CopyObject` would
    /// copy an encrypted envelope under the wrong destination key
    /// or write plaintext into an encrypted-bucket destination.
    private let encryptionGate: BucketEncryptionGate?

    init(
        browser: any S3Browsing,
        transferManager: TransferManager,
        activityLog: any ActivityLogging,
        encryptionGate: BucketEncryptionGate? = nil
    ) {
        self.browser = browser
        self.transferManager = transferManager
        self.activityLog = activityLog
        self.encryptionGate = encryptionGate
    }

    /// Perform the copy. `keepSource == false` deletes the source
    /// object after a successful destination write — i.e. "move".
    /// Returns the per-object outcome so the UI can summarise
    /// failures without exploding the error banner.
    @discardableResult
    func copy(
        sourceAccount: S3Account,
        sourceBucket: String,
        keys: [String],
        destinationAccount: S3Account,
        destinationBucket: String,
        destinationPrefix: String,
        keepSource: Bool
    ) async -> [(key: String, error: BucketeerError?)] {
        var results: [(key: String, error: BucketeerError?)] = []
        // Codex audit fix (high #1): once either side of the copy
        // touches a BYOK-protected bucket, we MUST go through the
        // round-trip path. Server-side `CopyObject` doesn't know
        // about Bucketeer envelopes and would otherwise produce
        // ciphertext encrypted under the wrong key (or plaintext
        // landing in an encrypted destination).
        let encryptionInvolved: Bool = await {
            guard let encryptionGate else { return false }
            if await encryptionGate.key(
                accountID: sourceAccount.id,
                bucket: sourceBucket
            ) != nil { return true }
            if await encryptionGate.key(
                accountID: destinationAccount.id,
                bucket: destinationBucket
            ) != nil { return true }
            return false
        }()
        let canServerCopy = !encryptionInvolved && Self.canServerSideCopy(
            from: sourceAccount,
            to: destinationAccount
        )
        for key in keys {
            let destinationKey = Self.composeDestinationKey(
                sourceKey: key,
                prefix: destinationPrefix
            )
            do {
                if canServerCopy {
                    try await browser.copy(
                        account: destinationAccount,
                        fromBucket: sourceBucket,
                        fromKey: key,
                        toBucket: destinationBucket,
                        toKey: destinationKey,
                        metadata: nil
                    )
                } else {
                    try await roundTripCopy(
                        sourceAccount: sourceAccount,
                        sourceBucket: sourceBucket,
                        sourceKey: key,
                        destinationAccount: destinationAccount,
                        destinationBucket: destinationBucket,
                        destinationKey: destinationKey
                    )
                }
                if !keepSource {
                    try await browser.delete(
                        account: sourceAccount,
                        bucket: sourceBucket,
                        keys: [key]
                    )
                }
                await activityLog.record(
                    ActivityEntry(
                        kind: .copy,
                        status: .success,
                        accountID: destinationAccount.id,
                        accountName: destinationAccount.name,
                        bucket: destinationBucket,
                        key: destinationKey,
                        message: "Cross-account from \(sourceAccount.name)/\(sourceBucket)/\(key)"
                    )
                )
                results.append((key, nil))
            } catch let error as BucketeerError {
                results.append((key, error))
                await activityLog.record(
                    ActivityEntry(
                        kind: .copy,
                        status: .failure,
                        accountID: destinationAccount.id,
                        accountName: destinationAccount.name,
                        bucket: destinationBucket,
                        key: destinationKey,
                        errorMessage: error.errorDescription
                    )
                )
            } catch {
                let bucketeerError = BucketeerError.unknown(message: error.localizedDescription)
                results.append((key, bucketeerError))
                await activityLog.record(
                    ActivityEntry(
                        kind: .copy,
                        status: .failure,
                        accountID: destinationAccount.id,
                        accountName: destinationAccount.name,
                        bucket: destinationBucket,
                        key: destinationKey,
                        errorMessage: error.localizedDescription
                    )
                )
            }
        }
        return results
    }

    // MARK: - Private

    /// Heuristic for "the destination account can issue a single
    /// `CopyObject` that pulls from the source bucket". Requires the
    /// same provider family and an exact endpoint match.
    static func canServerSideCopy(from src: S3Account, to dst: S3Account) -> Bool {
        guard src.provider.family == dst.provider.family else { return false }
        guard src.provider.family == .s3 else { return false }
        // Endpoint is computed from the provider+region+custom URL,
        // so equality here is the cleanest proxy for "the dest
        // account can address the src bucket without going through
        // the user's network."
        return S3ClientFactory.endpoint(for: src)
            == S3ClientFactory.endpoint(for: dst)
    }

    /// Download → upload via the existing TransferManager. Uses a
    /// temp file because TransferManager assumes the source for
    /// upload is a file URL.
    private func roundTripCopy(
        sourceAccount: S3Account,
        sourceBucket: String,
        sourceKey: String,
        destinationAccount: S3Account,
        destinationBucket: String,
        destinationKey: String
    ) async throws {
        // Codex audit fix (medium #3): keep the plaintext staging
        // file inside the App-private Application Support directory
        // and under a `bucketeer-roundtrip-*` prefix so the
        // launch-time scavenger (`CrossAccountCopyCoordinator.scavengeOrphans()`)
        // can clean up after a crash. `FileManager.temporaryDirectory`
        // is sandboxed already, but its retention is OS-decided —
        // App Support is under our control.
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let stagingDir = support.appending(path: "CrossAccountStaging")
        try? FileManager.default.createDirectory(
            at: stagingDir,
            withIntermediateDirectories: true
        )
        let temp = stagingDir
            .appendingPathComponent("bucketeer-roundtrip-\(UUID().uuidString)")
            .appendingPathExtension(URL(fileURLWithPath: sourceKey).pathExtension)
        // Installed before the download so a failed / cancelled first
        // half also cleans up its partial staging file — the launch
        // scavenger only covers crashes, not in-session failures.
        defer { try? FileManager.default.removeItem(at: temp) }

        let downloadID = await transferManager.enqueueDownload(
            account: sourceAccount,
            bucket: sourceBucket,
            key: sourceKey,
            localURL: temp
        )
        let downloadState = await transferManager.awaitCompletion(id: downloadID)
        switch downloadState {
        case .completed:
            break
        case .failed(let message):
            throw BucketeerError.unknown(message: message)
        case .cancelled:
            throw BucketeerError.cancelled
        default:
            throw BucketeerError.unknown(message: "Download did not finish.")
        }

        let uploadID = await transferManager.enqueueUpload(
            account: destinationAccount,
            bucket: destinationBucket,
            key: destinationKey,
            localURL: temp,
            contentType: nil
        )
        let uploadState = await transferManager.awaitCompletion(id: uploadID)
        switch uploadState {
        case .completed:
            return
        case .failed(let message):
            throw BucketeerError.unknown(message: message)
        case .cancelled:
            throw BucketeerError.cancelled
        default:
            throw BucketeerError.unknown(message: "Upload did not finish.")
        }
    }

    /// Sweep any leftover round-trip staging files. Called by
    /// `AppContainer.init` on every launch so a crash mid-copy
    /// doesn't leave plaintext on disk indefinitely. Codex audit
    /// fix (medium #3).
    // nonisolated: pure FileManager work, called from a detached
    // utility task at launch so it never blocks the main actor.
    nonisolated static func scavengeOrphans() {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? FileManager.default.temporaryDirectory
        let stagingDir = support.appending(path: "CrossAccountStaging")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: stagingDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        // Only reap files from a PREVIOUS session: the scavenger runs
        // detached at launch and must never race a round-trip copy the
        // user started seconds ago. Crash leftovers are by definition
        // older than the current process.
        let cutoff = Date().addingTimeInterval(-3600)
        for url in entries where url.lastPathComponent.hasPrefix("bucketeer-roundtrip-") {
            let modified = (try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ))?.contentModificationDate ?? .distantPast
            if modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// `prefix` may be empty, or end in `/` or not; either way we
    /// normalise so the destination key reproduces the source's
    /// filename inside the chosen prefix.
    static func composeDestinationKey(sourceKey: String, prefix: String) -> String {
        let trimmedPrefix = prefix.isEmpty
            ? ""
            : (prefix.hasSuffix("/") ? prefix : prefix + "/")
        // Use the source key's last segment as the filename — the
        // destination prefix supplies the parent path.
        let filename: String = {
            if let lastSlash = sourceKey.lastIndex(of: "/") {
                return String(sourceKey[sourceKey.index(after: lastSlash)...])
            }
            return sourceKey
        }()
        return trimmedPrefix + filename
    }
}
