//
//  EntitlementManager.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import StoreKit
import BucketeerCore

/// Single source of truth for what the user can do. Combines the
/// persisted trial timer with StoreKit's entitlement snapshot to
/// produce one of three observable states — `.trial(daysRemaining:)`,
/// `.free` and `.pro`.
///
/// The Pro pillars (mount, sync, cross-account copy, menubar) check
/// `isUnlocked(_:)` before doing real work; when locked they instead
/// present the paywall sheet.
///
/// **Provisioning:** the App Store Connect IAP product
/// `za.co.digitalfreedom.bucketeer.pro.lifetime` must exist (non-
/// consumable, single tier ~ €14.99, Family Sharing on). Local Debug
/// builds resolve it from `Bucketeer.storekit` via the scheme's
/// StoreKit configuration.
@MainActor
@Observable
final class EntitlementManager {
    enum State: Equatable, Sendable {
        case trial(daysRemaining: Int)
        case free
        case pro
    }

    enum ProFeature: String, Sendable, CaseIterable {
        case mountDrive
        case syncEngine
        case s3ToS3Copy
        case menubarBackground

        /// Localised label for the upsell sheet.
        var localizedKey: String {
            switch self {
            case .mountDrive:        return "paywall.feature.mountDrive"
            case .syncEngine:        return "paywall.feature.syncEngine"
            case .s3ToS3Copy:        return "paywall.feature.s3ToS3Copy"
            case .menubarBackground: return "paywall.feature.menubar"
            }
        }
    }

    enum EntitlementError: Error, LocalizedError {
        case productUnavailable
        case purchasePending
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .productUnavailable:
                return String(
                    localized: "paywall.error.productUnavailable",
                    defaultValue: "Bucketeer Pro is not available right now. Try again in a moment."
                )
            case .purchasePending:
                return String(
                    localized: "paywall.error.pending",
                    defaultValue: "Your purchase is pending. We'll unlock Pro as soon as it goes through."
                )
            case .unknown(let message):
                return message
            }
        }
    }

    static let proProductID = "za.co.digitalfreedom.bucketeer.pro.lifetime"

    /// Pure trial-state computation lives in Core's `TrialBookkeeping`
    /// so it can be regression-tested without StoreKit (Codex review #8
    /// mitigation — future-date clamp + sticky consumed marker).
    private let trial = TrialBookkeeping()

    private(set) var state: State = .free
    /// Resolved StoreKit product once `.products(for:)` returns. Nil
    /// while loading or if App Store Connect doesn't recognise the ID
    /// yet (TestFlight pre-provisioning).
    private(set) var product: Product?
    /// True while a purchase or restore is in flight.
    private(set) var purchaseInProgress: Bool = false

    private var transactionObserver: Task<Void, Never>?

    init() {
        ensureTrialStarted()
    }

    // MARK: - Public API

    /// Kick off StoreKit observation. Called from `AppContainer` after
    /// the SwiftData container is ready.
    func bootstrap() async {
        await loadProduct()
        await refresh()
        startTransactionObserver()
    }

    /// True when the supplied feature is allowed under the current
    /// entitlement state. Trial users get everything; Free users get
    /// the basics; Pro users get everything.
    func isUnlocked(_ feature: ProFeature) -> Bool {
        switch state {
        case .pro:
            return true
        case .trial:
            return true
        case .free:
            #if DEBUG
            // Debug builds bypass the paywall so day-to-day development
            // doesn't drown in upsell prompts. `#if DEBUG` is `false`
            // for Archive (TestFlight / App Store) builds — verify by
            // archiving locally before claiming a gating change is done.
            return true
            #else
            return false
            #endif
        }
    }

    /// Re-derive `state` from the persisted trial start and the live
    /// StoreKit entitlements.
    func refresh() async {
        if await hasActiveProEntitlement() {
            state = .pro
            return
        }
        if let days = trialDaysRemaining() {
            state = .trial(daysRemaining: days)
        } else {
            state = .free
        }
    }

    func purchasePro() async throws {
        guard let product else {
            throw EntitlementError.productUnavailable
        }
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refresh()
                }
            case .userCancelled:
                return
            case .pending:
                throw EntitlementError.purchasePending
            @unknown default:
                return
            }
        } catch let error as EntitlementError {
            throw error
        } catch {
            throw EntitlementError.unknown(error.localizedDescription)
        }
    }

    func restorePurchases() async throws {
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        do {
            try await AppStore.sync()
            await refresh()
        } catch {
            throw EntitlementError.unknown(error.localizedDescription)
        }
    }

    // MARK: - Trial

    private func ensureTrialStarted() {
        trial.start()
    }

    private func trialDaysRemaining() -> Int? {
        trial.daysRemaining()
    }

    // MARK: - StoreKit

    private func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            self.product = products.first
        } catch {
            self.product = nil
        }
    }

    private func hasActiveProEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let txn) = result,
               txn.productID == Self.proProductID,
               txn.revocationDate == nil {
                return true
            }
        }
        return false
    }

    private func startTransactionObserver() {
        guard transactionObserver == nil else { return }
        transactionObserver = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let txn) = update {
                    await txn.finish()
                }
                await self?.refresh()
            }
        }
    }
}
