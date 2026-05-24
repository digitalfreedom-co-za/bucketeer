//
//  AutoTagCoordinator.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import Observation
import UniformTypeIdentifiers
import BucketeerCore

/// Observes transfer completions and applies the user's auto-tagging
/// rules to every successful upload. Phase 13.8.
///
/// The coordinator is intentionally decoupled from `TransferManager`
/// so the rule lookup, MIME inference, and the rule-apply RPC chain
/// (CopyObject + PutObjectTagging) all happen in host code where
/// account snapshots are easy to reach.
///
/// Caching:
/// - The rule list is loaded once on `start()` and refreshed via
///   `reload()` whenever the editor saves a change. Each upload
///   completion reads the in-memory cache so the hot path doesn't
///   hit SwiftData.
///
/// Side effects:
/// - Only successful uploads (`TransferState.completed && direction
///   == .upload`) trigger rule application.
/// - Failures to apply are recorded via `ActivityLog` so the user can
///   see "tagging failed" without losing the upload they just made.
@MainActor
@Observable
final class AutoTagCoordinator {
    private let store: any AutoTagRuleStoring
    private let browser: any S3Browsing
    private let transferManager: TransferManager
    private let activityLog: any ActivityLogging
    private let accountStore: any AccountStoring

    private var rules: [AutoTagRule] = []
    private var observerTask: Task<Void, Never>?
    /// Tracks transfer IDs we have already evaluated so a re-yielded
    /// snapshot doesn't trigger a second rule pass for the same
    /// upload.
    private var evaluatedTransferIDs: Set<UUID> = []

    init(
        store: any AutoTagRuleStoring,
        browser: any S3Browsing,
        transferManager: TransferManager,
        activityLog: any ActivityLogging,
        accountStore: any AccountStoring
    ) {
        self.store = store
        self.browser = browser
        self.transferManager = transferManager
        self.activityLog = activityLog
        self.accountStore = accountStore
    }

    /// Begin observing the transfer manager's stream. Called once
    /// from `AppContainer` after the coordinator is constructed.
    func start() async {
        await reload()
        let stream = await transferManager.tasks
        observerTask?.cancel()
        observerTask = Task { [weak self] in
            for await snapshot in stream {
                await self?.handle(snapshot: snapshot)
            }
        }
    }

    /// Re-pull the rule list from the store. Called from the editor
    /// after a save.
    func reload() async {
        do {
            rules = try await store.all()
        } catch {
            // Best-effort — broken store means no auto-tagging, but
            // it must not crash the App.
            rules = []
        }
    }

    /// Per-snapshot dispatch. Looks for upload transfers that have
    /// just reached `.completed` and that we haven't evaluated yet.
    private func handle(snapshot: [TransferTask]) async {
        for task in snapshot where task.direction == .upload {
            switch task.state {
            case .completed:
                if !evaluatedTransferIDs.contains(task.id) {
                    evaluatedTransferIDs.insert(task.id)
                    await apply(to: task)
                }
            case .cancelled, .failed:
                evaluatedTransferIDs.remove(task.id)
            default:
                break
            }
        }
        // Drop tracking for transfers no longer present in the
        // snapshot to keep the set bounded.
        let live = Set(snapshot.map(\.id))
        evaluatedTransferIDs.formIntersection(live)
    }

    private func apply(to task: TransferTask) async {
        guard !rules.isEmpty else { return }
        let mime = inferMIME(for: task.localURL)
        let result = AutoTagRuleEvaluator.evaluate(
            rules: rules,
            filename: task.localURL.lastPathComponent,
            mime: mime
        )
        guard !result.tags.isEmpty || !result.userMetadata.isEmpty else { return }
        guard let account = await resolveAccount(id: task.accountID) else { return }

        do {
            // Read the current metadata so we MERGE the rule output
            // on top instead of clobbering anything the upload set.
            var current = try await browser.loadMetadata(
                account: account,
                bucket: task.bucket,
                key: task.key
            )
            current.userMetadata.merge(result.userMetadata) { _, new in new }
            current.tags.merge(result.tags) { _, new in new }
            try await browser.saveMetadata(
                account: account,
                bucket: task.bucket,
                key: task.key,
                metadata: current
            )
            await activityLog.record(
                ActivityEntry(
                    kind: .copy,
                    status: .success,
                    accountID: account.id,
                    accountName: account.name,
                    bucket: task.bucket,
                    key: task.key,
                    message: String(
                        localized: "autoTag.activity.applied",
                        defaultValue: "Auto-tagging applied."
                    )
                )
            )
        } catch let error as BucketeerError {
            // Most common cause: Azure provider, where the metadata
            // editor throws `featureNotSupported`. Silently skip
            // those to avoid noisy activity rows.
            if case .featureNotSupported = error { return }
            await activityLog.record(
                ActivityEntry(
                    kind: .copy,
                    status: .failure,
                    accountID: account.id,
                    accountName: account.name,
                    bucket: task.bucket,
                    key: task.key,
                    message: "Auto-tagging failed",
                    errorMessage: error.errorDescription
                )
            )
        } catch {
            await activityLog.record(
                ActivityEntry(
                    kind: .copy,
                    status: .failure,
                    accountID: account.id,
                    accountName: account.name,
                    bucket: task.bucket,
                    key: task.key,
                    message: "Auto-tagging failed",
                    errorMessage: error.localizedDescription
                )
            )
        }
    }

    private func resolveAccount(id: UUID) async -> S3Account? {
        do {
            let all = try await accountStore.all()
            return all.first(where: { $0.id == id })
        } catch {
            return nil
        }
    }

    private func inferMIME(for url: URL) -> String? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        return type.preferredMIMEType
    }
}
