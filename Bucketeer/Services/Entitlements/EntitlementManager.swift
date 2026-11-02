//
//  EntitlementManager.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import AppKit
import StoreKit
import BucketeerCore

/// Single source of truth for what the user can do. Reads the verified
/// StoreKit entitlements and lets Core's `ProAccessResolver` turn them
/// into one of three observable states — `.trial(daysRemaining:)`,
/// `.free` and `.pro`.
///
/// The trial is the free non-consumable `ProductIDs.trial`. It runs
/// for 14 days from that transaction's original purchase date; nothing
/// about it is stored locally, so Restore Purchases brings it back on
/// a new Mac and deleting app data cannot restart it.
///
/// The Pro pillars (mount, sync, cross-account copy, menubar) check
/// `isUnlocked(_:)` before doing real work; when locked they instead
/// present the paywall sheet.
///
/// **Provisioning:** both IAP products must exist in App Store Connect
/// (lifetime: non-consumable, Family Sharing on; trial: non-consumable,
/// price Free, Family Sharing off). Local Debug builds resolve them
/// from `Bucketeer.storekit` via the scheme's StoreKit configuration.
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

    private static let ownProductIDs: Set<String> = [ProductIDs.lifetime, ProductIDs.trial]

    private(set) var state: State = .free
    /// True while the user has never claimed the trial. The paywall
    /// only offers "Start trial" in that case.
    private(set) var isTrialAvailable: Bool = false
    /// Resolved StoreKit products once `.products(for:)` returns. Nil
    /// while loading or if App Store Connect doesn't recognise the ID
    /// yet (TestFlight pre-provisioning).
    private(set) var product: Product?
    private(set) var trialProduct: Product?
    /// True while a purchase or restore is in flight.
    private(set) var purchaseInProgress: Bool = false

    private let now: @Sendable () -> Date
    private var transactionObserver: Task<Void, Never>?
    private var activationObserver: Task<Void, Never>?
    /// Re-derives the state the moment a running trial ends, so an app
    /// left open across the expiry does not keep Pro unlocked.
    private var trialExpiryTimer: Task<Void, Never>?
    /// The launch-time state derivation. Uses StoreKit's on-device
    /// entitlements only, so it does not wait for the product request.
    private var initialRefresh: Task<Void, Never>?

    /// Called after every refresh. `AppContainer` uses it to switch
    /// off Pro-only modes once the entitlement lapses.
    var onStateChange: ((State) -> Void)?

    /// `fixedState` pins the state for tests and previews: no StoreKit.
    /// `nil` (the app) derives it. `now` is the clock the trial expiry
    /// is measured against.
    init(fixedState: State? = nil, now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
        if let fixedState {
            state = fixedState
            return
        }
        initialRefresh = Task { [weak self] in await self?.refresh() }
    }

    // MARK: - Public API

    /// Kick off StoreKit observation. Called from `AppContainer` after
    /// the SwiftData container is ready.
    func bootstrap() async {
        await initialRefresh?.value
        startTransactionObserver()
        startActivationObserver()
        await loadProducts()
    }

    /// `isUnlocked(_:)` for background work started at launch (on-launch
    /// sync jobs, watch folders): waits for the launch-time refresh so a
    /// Pro user's jobs are not refused while `state` is still `.free`.
    func isUnlockedAfterLaunchCheck(_ feature: ProFeature) async -> Bool {
        await initialRefresh?.value
        return isUnlocked(feature)
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

    /// Re-derive `state` from the live StoreKit entitlements.
    func refresh() async {
        trialExpiryTimer?.cancel()
        trialExpiryTimer = nil
        let reading = now()
        switch ProAccessResolver.resolve(await currentTransactions(), now: reading) {
        case .lifetime:
            state = .pro
            isTrialAvailable = false
        case .trial(let endsAt):
            state = .trial(daysRemaining: ProAccessResolver.daysRemaining(until: endsAt, now: reading))
            isTrialAvailable = false
            scheduleTrialExpiryRefresh(after: endsAt.timeIntervalSince(reading))
        case .trialEnded:
            state = .free
            isTrialAvailable = false
        case .trialAvailable:
            state = .free
            isTrialAvailable = true
        }
        onStateChange?(state)
    }

    func purchasePro() async throws {
        try await purchase(product)
    }

    /// Claims the free trial product. The trial clock starts with this
    /// transaction's purchase date.
    func startTrial() async throws {
        try await purchase(trialProduct)
    }

    func restorePurchases() async throws {
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        do {
            try await AppStore.sync()
            await refresh()
        } catch StoreKitError.userCancelled {
            // Dismissing the App Store sign-in prompt is a choice, not
            // a failure — mirror purchase()'s silent .userCancelled.
            return
        } catch {
            throw EntitlementError.unknown(error.localizedDescription)
        }
    }

    // MARK: - Purchase

    private func purchase(_ product: Product?) async throws {
        guard let product else {
            throw EntitlementError.productUnavailable
        }
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refresh()
                case .unverified(_, let verificationError):
                    // Surface it instead of swallowing it, so the
                    // paywall can show what happened.
                    throw EntitlementError.unknown(
                        verificationError.localizedDescription
                    )
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

    // MARK: - Trial expiry

    private func scheduleTrialExpiryRefresh(after seconds: TimeInterval) {
        trialExpiryTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(seconds, 0)))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Backstop for the expiry timer: re-check whenever the app becomes
    /// active.
    private func startActivationObserver() {
        guard activationObserver == nil else { return }
        activationObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                await self?.refresh()
            }
        }
    }

    // MARK: - StoreKit

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: Self.ownProductIDs)
            product = products.first { $0.id == ProductIDs.lifetime }
            trialProduct = products.first { $0.id == ProductIDs.trial }
        } catch {
            product = nil
            trialProduct = nil
        }
    }

    /// Verified transactions for our products. Unverified ones never
    /// unlock anything.
    private func currentTransactions() async -> [StoreTransactionRecord] {
        var records: [StoreTransactionRecord] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let txn) = result,
                  Self.ownProductIDs.contains(txn.productID)
            else { continue }
            records.append(StoreTransactionRecord(
                productID: txn.productID,
                originalPurchaseDate: txn.originalPurchaseDate,
                revocationDate: txn.revocationDate
            ))
        }
        return records
    }

    private func startTransactionObserver() {
        guard transactionObserver == nil else { return }
        transactionObserver = Task { [weak self] in
            for await update in Transaction.updates {
                // Finish only OUR products' transactions. Blindly
                // finishing everything would consume a future
                // consumable IAP before its value is credited.
                if case .verified(let txn) = update,
                   Self.ownProductIDs.contains(txn.productID) {
                    await txn.finish()
                }
                await self?.refresh()
            }
        }
    }
}
