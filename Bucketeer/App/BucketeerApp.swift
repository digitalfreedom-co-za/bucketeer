//
//  BucketeerApp.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI
import AppKit

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
        // Hand the controller to the delegate so it can answer
        // `applicationShouldTerminateAfterLastWindowClosed` correctly.
        BucketeerAppDelegate.shared.activationController = container.activationController
    }

    var body: some Scene {
        Window("app.name", id: "main") {
            ContentView()
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

        Settings {
            SettingsView()
                .environment(container)
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

        // Keep ⌘N reserved for the (future) account-add menu action.
        CommandGroup(replacing: .newItem) {
            Button("action.add-account") {
                // Wired up to the main-window sidebar in a later phase.
            }
            .keyboardShortcut("n", modifiers: .command)
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
                destination: URL(string: "https://github.com/digitalfreedom-co-za/bucketeer/issues/new")!
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
    /// Static reference so the `@main` struct can pass the controller
    /// in from its init. The alternative — environment lookup inside
    /// the delegate — does not work because the delegate runs *before*
    /// any SwiftUI environment exists.
    static let shared = BucketeerAppDelegate()

    var activationController: AppActivationController?

    override init() {
        super.init()
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
