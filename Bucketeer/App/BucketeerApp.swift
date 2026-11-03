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
            container = try Self.makeContainer()
        } catch {
            fatalError("Failed to initialise AppContainer: \(error)")
        }
        _container = State(initialValue: container)
        // Phase 13.12 — expose the live container to App Intents,
        // which run inside the host process but cannot reach
        // SwiftUI state directly.
        AppContainer.shared = container
        // Inject the activation controller into the **adaptor-managed**
        // delegate instance, not a separate singleton.
        // the adaptor creates a fresh BucketeerAppDelegate at launch;
        // assigning to a `static let shared` left the live delegate
        // with `activationController == nil`, so menubar mode never
        // applied at launch and the "quit after last window closed"
        // logic always saw `false`.
        BucketeerAppDelegate.installedActivationController = container.activationController
    }

    /// Debug builds of the QA copy launched with `-BucketeerScreenshotDemo YES`
    /// get a seeded in-memory demo container instead of the user's data.
    private static func makeContainer() throws -> AppContainer {
        #if DEBUG
        if let launch = ScreenshotDemoLaunch.current {
            return try ScreenshotDemoDirector.makeContainer(for: launch)
        }
        #endif
        return try AppContainer()
    }

    var body: some Scene {
        Window("app.name", id: "main") {
            // Phase 13.11 — wrap the content so we have access to
            // `@Environment(\.openWindow)` for routing deep links
            // (the App protocol itself doesn't expose environment
            // properties).
            DeepLinkAwareContent()
                .environment(container)
                .honeyAccent()
        }
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands()
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(container)
                .honeyAccent()
        } label: {
            Image(systemName: "externaldrive.connected.to.line.below")
                .accessibilityLabel(Text("app.name"))
        }
        .menuBarExtraStyle(.window)

        Window("about.title", id: "about") {
            AboutWindow()
                .honeyAccent()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("help.title", id: "help") {
            HelpWindow()
                .honeyAccent()
        }
        .defaultSize(width: 800, height: 700)
        .defaultPosition(.center)

        Window("activity.window.title", id: "activity") {
            ActivityLogView()
                .frame(minWidth: 880, minHeight: 480)
                #if DEBUG
                .modifier(ScreenshotDemoWindow(size: ScreenshotDemoDirector.mainWindowSize))
                #endif
                .environment(container)
                .honeyAccent()
        }
        .defaultSize(width: 1000, height: 600)
        .defaultPosition(.center)

        Window("trash.window.title", id: "trash") {
            TrashView()
                .environment(container)
                .frame(minWidth: 900, minHeight: 480)
                .honeyAccent()
        }
        .defaultSize(width: 1000, height: 580)
        .defaultPosition(.center)

        // Phase 14 — dedicated detail window so `bucketeer://sync/<id>`
        // deep links open a focused per-job view instead of just
        // bringing the main window forward. Uses WindowGroup
        // (per-value) so multiple sync jobs can be open side-by-side.
        WindowGroup("syncDetail.window.title", id: "sync-job", for: UUID.self) { $jobID in
            if let jobID {
                SyncJobDetailWindow(jobID: jobID)
                    .environment(container)
                    .honeyAccent()
            } else {
                ContentUnavailableView(
                    "syncDetail.error.title",
                    systemImage: "exclamationmark.triangle",
                    description: Text("syncDetail.error.noID")
                )
            }
        }
        .defaultSize(width: 600, height: 480)

        Settings {
            SettingsView()
                .environment(container)
                .honeyAccent()
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
        // do something useful. A stubbed no-op menu item
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

    /// Files opened with another app may still have a save waiting to
    /// be uploaded; finish that and remove the temp copies first. Edits
    /// that could not be uploaded are kept, and the user may stay to
    /// deal with them.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let openWith = AppContainer.shared?.openWithController, openWith.hasOpenFiles else {
            return .terminateNow
        }
        Task {
            let kept = await openWith.flushAndRemoveAll()
            sender.reply(toApplicationShouldTerminate: kept == 0 || openWith.confirmQuit(keeping: kept))
        }
        return .terminateLater
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
