//
//  RedeemCodeButton.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import SwiftUI
import StoreKit

/// Opens Apple's offer code redemption sheet. The SwiftUI sheet needs
/// macOS 15, so the button is not shown on macOS 14. A redeemed code
/// unlocks like a purchase: the entitlement is re-checked right away,
/// and `Transaction.updates` in `EntitlementManager` finishes the
/// transaction.
struct RedeemCodeButton: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        if #available(macOS 15.0, *) {
            RedeemCodeSheetButton(entitlementManager: container.entitlementManager)
        }
    }
}

@available(macOS 15.0, *)
private struct RedeemCodeSheetButton: View {
    let entitlementManager: EntitlementManager

    @State private var isRedeeming = false

    var body: some View {
        Button("paywall.button.redeemCode") { isRedeeming = true }
            .disabled(entitlementManager.purchaseInProgress)
            .offerCodeRedemption(isPresented: $isRedeeming) { result in
                if case .success = result {
                    Task { await entitlementManager.refresh() }
                }
            }
    }
}
