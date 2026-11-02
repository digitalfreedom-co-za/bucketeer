//
//  AppActivationController.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import AppKit
import Foundation
import Observation

/// Tracks the "Run in background" preference and applies the matching
/// NSApplication activation policy. Persisted in UserDefaults so the
/// setting survives across launches.
///
/// Policy mapping:
/// - **Menubar mode ON** (`accessory`): no Dock icon, app keeps running
///   when every window is closed, control lives in the menubar.
/// - **Menubar mode OFF** (`regular`): standard Dock app behaviour, last
///   window close ends the process.
@MainActor
@Observable
final class AppActivationController {
    static let preferenceKey = "bucketeer.menubarMode"

    private(set) var menubarMode: Bool

    init() {
        self.menubarMode = UserDefaults.standard.bool(forKey: Self.preferenceKey)
    }

    /// Apply the current preference to the running app. Called once at
    /// launch from the AppDelegate; idempotent.
    func applyOnLaunch() {
        applyPolicy(animated: false)
    }

    func setMenubarMode(_ enabled: Bool) {
        guard menubarMode != enabled else { return }
        menubarMode = enabled
        UserDefaults.standard.set(enabled, forKey: Self.preferenceKey)
        applyPolicy(animated: true)
    }

    private func applyPolicy(animated: Bool) {
        let policy: NSApplication.ActivationPolicy = menubarMode ? .accessory : .regular
        NSApp.setActivationPolicy(policy)
        if !menubarMode {
            // Switching back to regular: bring the Dock icon up and the
            // (probably) hidden main window with it so the user knows
            // the change took effect.
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
