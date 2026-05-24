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
    var isLoading: Bool = false
    var error: BucketeerError?

    private let collector: BucketStatsCollector
    private var loadTask: Task<Void, Never>?

    init(account: S3Account, bucket: String, browser: any S3Browsing) {
        self.account = account
        self.bucket = bucket
        self.collector = BucketStatsCollector(browser: browser)
    }

    func reload() {
        loadTask?.cancel()
        let collector = collector
        let account = account
        let bucket = bucket
        isLoading = true
        error = nil
        loadTask = Task { [weak self] in
            do {
                let result = try await collector.collect(account: account, bucket: bucket)
                if Task.isCancelled { return }
                self?.stats = result
                self?.isLoading = false
            } catch is CancellationError {
                self?.isLoading = false
            } catch let bucketeerError as BucketeerError {
                self?.error = bucketeerError
                self?.isLoading = false
            } catch {
                self?.error = .unknown(message: error.localizedDescription)
                self?.isLoading = false
            }
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
