//
//  SpotlightSettings.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import Observation

/// User-tunable Spotlight indexing toggle. Phase 13.13. Defaults to
/// **off** — Spotlight indexing exposes object filenames system-wide
/// which is a real privacy decision; we want the user to opt in
/// explicitly.
@MainActor
@Observable
final class SpotlightSettings {
    private static let enabledKey = "spotlight.indexing.enabled"
    private let defaults: UserDefaults

    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Self.enabledKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enabled = defaults.bool(forKey: Self.enabledKey)
    }
}
