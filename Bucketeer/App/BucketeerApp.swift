//
//  BucketeerApp.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI

@main
struct BucketeerApp: App {
    @State private var container: AppContainer

    init() {
        let container: AppContainer
        do {
            container = try AppContainer()
        } catch {
            fatalError("Failed to initialise AppContainer: \(error)")
        }
        _container = State(initialValue: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(container)
        }
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands()
        }

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

private struct SettingsView: View {
    var body: some View {
        Form {
            Section("settings.section.general") {
                Text("settings.placeholder")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 320)
    }
}
