//
//  PaywallSheet.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import SwiftUI
import StoreKit

/// Single-page upsell shown when a Free user reaches a gated feature
/// (mount, sync, cross-account copy, menubar) or opens Settings → Pro.
/// One product, one price, one button — no funnel, no nag.
struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(AppContainer.self) private var container

    /// Optional context — when present we lead with the feature the
    /// user just tried to access ("Unlock Mount to use this").
    let feature: EntitlementManager.ProFeature?

    @State private var purchaseError: String?

    var body: some View {
        VStack(spacing: 24) {
            header
            bulletList
            priceCard
            footer
        }
        .padding(36)
        .frame(width: 480)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("paywall.title")
                .font(.title)
                .bold()
            if let feature {
                Text(LocalizedStringKey(feature.localizedKey))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if case .trial(let days) = container.entitlementManager.state {
                Text("paywall.trial.remaining \(days)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("paywall.subtitle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var bulletList: some View {
        VStack(alignment: .leading, spacing: 12) {
            bullet("paywall.bullet.mount", icon: "externaldrive.badge.plus")
            bullet("paywall.bullet.sync", icon: "arrow.triangle.2.circlepath")
            bullet("paywall.bullet.crossAccount", icon: "rectangle.2.swap")
            bullet("paywall.bullet.menubar", icon: "menubar.rectangle")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(_ key: LocalizedStringKey, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(key)
        }
    }

    @ViewBuilder
    private var priceCard: some View {
        let entitlement = container.entitlementManager
        VStack(spacing: 8) {
            Button {
                Task { await purchase() }
            } label: {
                Group {
                    if let product = entitlement.product {
                        Text("paywall.button.buy \(product.displayPrice)")
                    } else {
                        Text("paywall.button.buy.fallback")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(entitlement.purchaseInProgress)

            Text("paywall.button.subtitle")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("paywall.button.restore") {
                Task { await restore() }
            }
            .buttonStyle(.borderless)
            .disabled(entitlement.purchaseInProgress)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 6) {
            Text("paywall.familySharing")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            HStack(spacing: 16) {
                Button("paywall.link.eula") {
                    openAboutSection(.eula)
                }
                .buttonStyle(.link)
                Button("paywall.link.privacy") {
                    openAboutSection(.privacy)
                }
                .buttonStyle(.link)
                Button("paywall.link.refund") {
                    if let url = URL(string: "https://reportaproblem.apple.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
            .font(.footnote)
            if let purchaseError {
                Text(purchaseError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
            HStack {
                Spacer()
                Button("action.cancel") { dismiss() }
                    .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Actions

    /// Open the About window on a specific legal section. The paywall
    /// sheet stays up — the About window comes to the front so the
    /// user can read and come back.
    private func openAboutSection(_ section: AboutWindow.Section) {
        openWindow(id: "about")
        // Post async so the window exists before the section switch
        // lands — onReceive subscribes on first render.
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .showBucketeerAboutSection,
                object: section
            )
        }
    }

    private func purchase() async {
        purchaseError = nil
        do {
            try await container.entitlementManager.purchasePro()
            if case .pro = container.entitlementManager.state {
                dismiss()
            }
        } catch let error as EntitlementManager.EntitlementError {
            purchaseError = error.errorDescription
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func restore() async {
        purchaseError = nil
        do {
            try await container.entitlementManager.restorePurchases()
            if case .pro = container.entitlementManager.state {
                dismiss()
            }
        } catch let error as EntitlementManager.EntitlementError {
            purchaseError = error.errorDescription
        } catch {
            purchaseError = error.localizedDescription
        }
    }
}
