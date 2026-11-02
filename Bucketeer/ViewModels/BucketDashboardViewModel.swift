//
//  BucketDashboardViewModel.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import BucketeerCore

/// Drives the **Bucket Dashboard** sheet. Phase 13.5.
///
/// Walks the whole bucket on demand via `BucketStatsCollector`; the
/// view triggers an initial load on appear and a manual refresh via
/// a button. Cancels any in-flight walk if the user dismisses the
/// sheet so we don't keep paging the bucket needlessly.
@MainActor
@Observable
final class BucketDashboardViewModel {
    let account: S3Account
    let bucket: String

    var stats: BucketStats?
    /// Phase 13.9 — lifecycle / CORS / policy snapshot fetched in
    /// parallel with the stats walk. `nil` while loading, set to a
    /// possibly-empty `BucketInsights` once the load completes, or
    /// left at `nil` if the provider returns `.featureNotSupported`.
    var insights: BucketInsights?
    /// Captured separately so the UI can show a "not supported"
    /// banner rather than just blank panels.
    var insightsError: BucketeerError?
    var isLoading: Bool = false
    var error: BucketeerError?

    private let collector: BucketStatsCollector
    private let browser: any S3Browsing
    private var loadTask: Task<Void, Never>?

    init(account: S3Account, bucket: String, browser: any S3Browsing) {
        self.account = account
        self.bucket = bucket
        self.collector = BucketStatsCollector(browser: browser)
        self.browser = browser
    }

    func reload() {
        loadTask?.cancel()
        let collector = collector
        let browser = browser
        let account = account
        let bucket = bucket
        isLoading = true
        error = nil
        insightsError = nil
        loadTask = Task { [weak self] in
            // Plain `async let` (no inner Task wrappers): the children
            // are structured, so cancelling `loadTask` when the sheet
            // closes actually stops the bucket walk instead of letting
            // it page on in the background.
            async let statsTask = collector.collect(account: account, bucket: bucket)
            // Phase 13.9 — pull insights in parallel with the stats
            // walk so the dashboard reveals lifecycle / CORS / policy
            // info as soon as both come back. Insight failures are
            // captured separately so a missing-policy provider
            // doesn't blank out the stats panel.
            async let insightsTask = browser.loadInsights(account: account, bucket: bucket)
            do {
                let result = try await statsTask
                if Task.isCancelled { return }
                self?.stats = result
            } catch is CancellationError {
                // Cancellation = user closed the sheet. Bail.
            } catch let bucketeerError as BucketeerError {
                self?.error = bucketeerError
            } catch {
                self?.error = .unknown(message: error.localizedDescription)
            }
            do {
                self?.insights = try await insightsTask
            } catch let bucketeerError as BucketeerError {
                self?.insightsError = bucketeerError
            } catch {
                self?.insightsError = .unknown(message: error.localizedDescription)
            }
            self?.isLoading = false
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    /// Estimated monthly storage cost in USD, or `nil` if either the
    /// stats haven't loaded yet or the provider has no pricing entry.
    var monthlyCostUSD: Double? {
        guard let stats else { return nil }
        return ProviderPricing.estimateMonthlyUSD(
            bytes: stats.totalBytes,
            provider: account.provider
        )
    }
}
