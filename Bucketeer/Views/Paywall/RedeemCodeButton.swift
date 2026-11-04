//
//  RedeemCodeButton.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import SwiftUI
import StoreKit

/// Opens Apple's offer code redemption sheet. A redeemed code unlocks
/// like a purchase: the entitlement is re-checked right away, and
/// `Transaction.updates` in `EntitlementManager` finishes the
/// transaction.
struct RedeemCodeButton: View {
    @Environment(AppContainer.self) private var container

    @State private var isRedeeming = false

    var body: some View {
        let entitlementManager = container.entitlementManager
        Button("paywall.button.redeemCode") { isRedeeming = true }
            .disabled(entitlementManager.purchaseInProgress)
            .offerCodeRedemption(isPresented: $isRedeeming) { result in
                if case .success = result {
                    Task { await entitlementManager.refresh() }
                }
            }
    }
}
