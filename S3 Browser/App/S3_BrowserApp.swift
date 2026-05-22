//
//  S3_BrowserApp.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI

@main
struct S3_BrowserApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("action.add-account", systemImage: "plus") {
                    // wired up in Phase 2
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
