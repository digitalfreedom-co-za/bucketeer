//
//  BucketeerApp.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI
import AppKit
import CoreSpotlight
import BucketeerCore

@main
struct BucketeerApp: App {
    @State private var container: AppContainer
    @NSApplicationDelegateAdaptor(BucketeerAppDelegate.self) private var appDelegate

    init() {
        let container: AppContainer
        do {
            container = try AppContainer()
        } catch {
            fatalError("Failed to initialise AppContainer: \(error)")
        }
        _container = State(initialValue: container)
        // Phase 13.12 — expose the live container to App Intents,
        // which run inside the host process but cannot reach
        // SwiftUI state directly.
        AppContainer.shared = container
        // Inject the activation controller into the **adaptor-managed**
        // delegate instance, not a separate singleton. Codex high #5:
        // the adaptor creates a fresh BucketeerAppDelegate at launch;
        // assigning to a `static let shared` left the live delegate
        // with `activationController == nil`, so menubar mode never
        // applied at launch and the "quit after last window closed"
        // logic always saw `false`.
        BucketeerAppDelegate.installedActivationController = container.activationController
    }

    var body: some Scene {
        Window("app.name", id: "main") {
            // Phase 13.11 — wrap the content so we have access to
            // `@Environment(\.openWindow)` for routing deep links
            // (the App protocol itself doesn't expose environment
            // properties).
            DeepLinkAwareContent()
                .environment(container)
        }
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands()
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(container)
        } label: {
            Image(systemName: "externaldrive.connected.to.line.below")
                .accessibilityLabel(Text("app.name"))
        }
        .menuBarExtraStyle(.window)

        Window("about.title", id: "about") {
            AboutWindow()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("help.title", id: "help") {
            HelpWindow()
        }
        .defaultSize(width: 800, height: 700)
        .defaultPosition(.center)

        Window("activity.window.title", id: "activity") {
            ActivityLogView()
                .environment(container)
                .frame(minWidth: 880, minHeight: 480)
        }
        .defaultSize(width: 1000, height: 600)
        .defaultPosition(.center)

        Window("trash.window.title", id: "trash") {
            TrashView()
                .environment(container)
                .frame(minWidth: 900, minHeight: 480)
        }
        .defaultSize(width: 1000, height: 580)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environment(container)
        }
    }
}

/// Hosting wrapper that injects SwiftUI's `OpenWindowAction` into
/// the deep-link router. Lives here because the App protocol can't
/// declare `@Environment` properties — the wrapper view can.
private struct DeepLinkAwareContent: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView()
            .onOpenURL { url in
                container.deepLinkRouter.handle(url: url, openWindow: openWindow)
            }
            .onReceive(NotificationCenter.default.publisher(for: .bucketeerDeepLinkReceived)) { note in
                if let link = note.object as? BucketeerDeepLink {
                    container.deepLinkRouter.handle(link, openWindow: openWindow)
                }
            }
            // Phase 13.13 — Spotlight click hands us an
            // NSUserActivity whose `userInfo` carries the item's
            // `uniqueIdentifier` under `CSSearchableItemActivityIdentifier`.
            // We stored the deep-link URL there at index time, so
            // routing is the same path as an external `open`.
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                if let raw = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                   let url = URL(string: raw) {
                    container.deepLinkRouter.handle(url: url, openWindow: openWindow)
                }
            }
    }
}

private struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Replace the default "About Bucketeer" item with one that
        // opens the custom multi-section About window.
        CommandGroup(replacing: .appInfo) {
            Button("menu.app.about") {
                openWindow(id: "about")
            }
        }

        // The default New File / New Window items are noise for an
        // object-storage browser. Drop them entirely; the "+ Add account"
        // affordance lives in the sidebar where it has the context to
        // do something useful. Codex low #15: a stubbed no-op menu item
        // is shipped dead code.
        CommandGroup(replacing: .newItem) {}

        // Window menu — surface the Activity Log so users can find it
        // without going through Help. Phase 13.1.
        CommandGroup(after: .windowArrangement) {
            Button("menu.window.activity") {
                openWindow(id: "activity")
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
            Button("menu.window.trash") {
                openWindow(id: "trash")
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }

        // Replace the default Help menu with our own entries.
        CommandGroup(replacing: .help) {
            Button("menu.help.quickStart") {
                openWindow(id: "help")
            }
            .keyboardShortcut("?", modifiers: .command)

            Divider()

            Link(
                "menu.help.github",
                destination: URL(string: "https://github.com/digitalfreedom-co-za/bucketeer")!
            )
            Link(
                "menu.help.issue",
                destination: URL(string: "https://support.apps.digitalfreedom.co.za/")!
            )
            Link(
                "menu.help.website",
                destination: URL(string: "https://digitalfreedom.co.za")!
            )

            Divider()

            Button("menu.help.privacyPolicy") {
                openWindow(id: "about")
            }
            Button("menu.help.eula") {
                openWindow(id: "about")
            }
        }
    }
}

/// AppKit delegate that customises window-close semantics for menubar
/// mode and applies the saved activation policy on launch. SwiftUI
/// alone has no clean hook for either piece, so a tiny delegate fills
/// the gap. MainActor-bound because `NSApplicationDelegate` callbacks
/// only ever fire on the main thread and the singleton must be safe to
/// touch from the SwiftUI app init.
@MainActor
final class BucketeerAppDelegate: NSObject, NSApplicationDelegate {
    /// Hand-off slot for the activation controller. `BucketeerApp.init`
    /// writes here *before* SwiftUI instantiates the adaptor's delegate,
    /// so by the time `applicationDidFinishLaunching` fires the static
    /// has the live controller. The delegate copies it onto an instance
    /// property on init so subsequent App switches between menubar /
    /// regular mode keep working without going through the static.
    nonisolated(unsafe) static var installedActivationController: AppActivationController?

    var activationController: AppActivationController?

    override init() {
        super.init()
        self.activationController = Self.installedActivationController
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        activationController?.applyOnLaunch()
    }

    /// In menubar mode the app should keep running with the main window
    /// closed. Out of menubar mode the conventional macOS behaviour
    /// applies — closing the last window quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(activationController?.menubarMode ?? false)
    }

    /// Re-open the main window when the user clicks the (now-absent)
    /// Dock icon in regular mode or selects the app from the App
    /// Switcher with no windows open.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }
}

/// Settings shell — General (incl. menubar toggle, gated by Pro) plus
/// the Pro tab that surfaces the entitlement state and the buy / restore
/// affordances.
private struct SettingsView: View {
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
                        Task { try? await entitlement.restorePurchases() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
