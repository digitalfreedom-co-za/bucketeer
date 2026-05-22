//
//  S3_BrowserApp.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI

@main
struct S3_BrowserApp: App {
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
            CommandGroup(replacing: .newItem) {
                Button("action.add-account") {
                    // Wired up in Phase 3 when account-creation menu action
                    // becomes coupled to the visible window.
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(container)
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
