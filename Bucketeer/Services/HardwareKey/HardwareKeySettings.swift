//
//  HardwareKeySettings.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import Observation

/// User-tunable hardware-key unlock preferences. Phase 13.16.
///
/// Defaults to **off**. When `enabled` is `true`, the secret-reveal
/// path attempts a smartcard / token PIN challenge first and falls
/// back to Touch-ID on failure or when no reader is detected.
///
/// Honest about scope: the full PIN-challenge → unlock gate ships as
/// **technical preview** in v1.16 because real-device validation
/// against multiple YubiKey / PIV combinations needs a wider hardware
/// test pass before it can replace the Touch-ID path outright.
@MainActor
@Observable
final class HardwareKeySettings {
    private static let enabledKey = "hardwareKey.enabled"
    private static let preferredSlotKey = "hardwareKey.preferredSlot"

    private let defaults: UserDefaults

    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Self.enabledKey) }
    }

    /// Optional slot name the user pinned in the Settings list.
    /// Cleared to `nil` when the user picks "Any token".
    var preferredSlot: String? {
        didSet { defaults.set(preferredSlot, forKey: Self.preferredSlotKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enabled = defaults.bool(forKey: Self.enabledKey)
        self.preferredSlot = defaults.string(forKey: Self.preferredSlotKey)
    }
}
