//
//  SettingsView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI
import AppKit
import BucketeerCore

/// Settings shell — General (incl. menubar toggle, gated by Pro) plus
/// the Pro tab that surfaces the entitlement state and the buy / restore
/// affordances.
struct SettingsView: View {
    @State private var restoreError: String?
    @Environment(AppContainer.self) private var container
    @State private var showingPaywall: Bool = false

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("settings.tab.general", systemImage: "gearshape")
                }
            transfersTab
                .tabItem {
                    Label("settings.tab.transfers", systemImage: "arrow.up.arrow.down.circle")
                }
            // Phase 13.8 — auto-tagging rules.
            AutoTagRulesView()
                .environment(container)
                .tabItem {
                    Label("settings.tab.rules", systemImage: "tag")
                }
            // Phase 13.15 — per-bucket BYOK encryption keys.
            EncryptionKeysView()
                .environment(container)
                .tabItem {
                    Label("settings.tab.encryption", systemImage: "lock.shield")
                }
            // Phase 13.16 — hardware-key (CryptoTokenKit) unlock.
            HardwareKeyView()
                .environment(container)
                .tabItem {
                    Label("settings.tab.security", systemImage: "key.fill")
                }
            proTab
                .tabItem {
                    Label("settings.tab.pro", systemImage: "shippingbox.and.arrow.backward.fill")
                }
        }
        .frame(minWidth: 520, minHeight: 360)
        .sheet(isPresented: $showingPaywall) {
            PaywallSheet(feature: nil)
                .environment(container)
        }
    }

    /// Phase 13.2 — global bandwidth throttle. Honest about scope: the
    /// cap is accurate end-to-end for Azure (the transporter owns
    /// every wire chunk) and best-effort for Soto S3 multipart, where
    /// the bucket is charged per progress callback delta rather than
    /// per wire byte.
    private var transfersTab: some View {
        @Bindable var bandwidthSettings = container.bandwidthSettings
        @Bindable var trashSettings = container.trashSettings
        return Form {
            Section("settings.transfers.section.bandwidth") {
                Picker("settings.transfers.bandwidth.cap", selection: $bandwidthSettings.selectedPreset) {
                    ForEach(BandwidthSettings.Preset.allCases) { preset in
                        Text(LocalizedStringKey(preset.labelKey)).tag(preset)
                    }
                }
                if bandwidthSettings.selectedPreset == .custom {
                    Stepper(value: $bandwidthSettings.customMegabytesPerSecond, in: 1...512) {
                        Text(
                            String(
                                format: NSLocalizedString("settings.transfers.bandwidth.custom", comment: ""),
                                bandwidthSettings.customMegabytesPerSecond
                            )
                        )
                    }
                }
                Text("settings.transfers.bandwidth.note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            // Phase 13.13 — Spotlight indexing toggle (opt-in).
            Section("settings.spotlight.section") {
                @Bindable var spotlightSettings = container.spotlightSettings
                Toggle("settings.spotlight.toggle", isOn: $spotlightSettings.enabled)
                    .onChange(of: spotlightSettings.enabled) { _, newValue in
                        if !newValue {
                            Task { await container.spotlightIndexer.purgeAll() }
                        }
                    }
                Text("settings.spotlight.note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            // Phase 13.4 — soft-delete trash behaviour.
            Section("settings.transfers.section.trash") {
                Toggle("settings.trash.cache.enabled", isOn: $trashSettings.cacheEnabled)
                Stepper(value: $trashSettings.cacheCapMB, in: 0...2048, step: 25) {
                    Text(
                        String(
                            format: NSLocalizedString("settings.trash.cache.cap", comment: ""),
                            trashSettings.cacheCapMB
                        )
                    )
                }
                .disabled(!trashSettings.cacheEnabled)
                Stepper(value: $trashSettings.retentionDays, in: 1...365) {
                    Text(
                        String(
                            format: NSLocalizedString("settings.trash.retention", comment: ""),
                            trashSettings.retentionDays
                        )
                    )
                }
                Text("settings.trash.note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var generalTab: some View {
        Form {
            Section("settings.section.general") {
                let menubar = Binding<Bool>(
                    get: { container.activationController.menubarMode },
                    set: { newValue in
                        if newValue && !container.entitlementManager.isUnlocked(.menubarBackground) {
                            showingPaywall = true
                            return
                        }
                        container.activationController.setMenubarMode(newValue)
                    }
                )
                Toggle("settings.menubar.toggle", isOn: menubar)
                if !container.entitlementManager.isUnlocked(.menubarBackground) {
                    Label("settings.menubar.proBadge", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("settings.menubar.description")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var proTab: some View {
        let entitlement = container.entitlementManager
        Form {
            Section("settings.pro.section.status") {
                LabeledContent("settings.pro.status") {
                    switch entitlement.state {
                    case .pro:
                        Label("settings.pro.status.pro", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.tint)
                    case .trial(let days):
                        Text("settings.pro.status.trial \(days)")
                    case .free:
                        Text("settings.pro.status.free")
                    }
                }
                if case .pro = entitlement.state {
                    Text("settings.pro.thanks")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button("settings.pro.buy") {
                        showingPaywall = true
                    }
                    .buttonStyle(.borderedProminent)
                    Button("settings.pro.restore") {
                        Task {
                            restoreError = nil
                            do {
                                try await entitlement.restorePurchases()
                            } catch {
                                // A silently-failing restore button is
                                // indistinguishable from a broken one.
                                restoreError = (error as? LocalizedError)?
                                    .errorDescription ?? error.localizedDescription
                            }
                        }
                    }
                    RedeemCodeButton()
                    if let restoreError {
                        Text(restoreError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
