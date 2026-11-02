//
//  TrashSettings.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import Observation

/// User-tunable retention + cache-size cap for the soft-delete trash.
/// Phase 13.4. Defaults strike a balance between "I can undo a
/// mistake" and "don't silently consume gigabytes of disk".
@MainActor
@Observable
final class TrashSettings {
    /// Days a trash entry is retained before `purgeExpired` removes
    /// it. Default 30 — long enough to catch "what did I do
    /// yesterday?" without growing the cache forever.
    private static let retentionKey = "trash.retentionDays"
    /// Maximum file size (in MB) for which a cached payload is
    /// downloaded after deletion. Files above the cap are
    /// metadata-only (`.skippedTooLarge`).
    private static let cacheCapKey = "trash.cacheCapMB"
    /// Master toggle. When `false`, no payload is ever cached
    /// regardless of `cacheCapMB`.
    private static let enableCacheKey = "trash.cacheEnabled"

    private let defaults: UserDefaults

    var retentionDays: Int {
        didSet {
            retentionDays = max(1, min(365, retentionDays))
            defaults.set(retentionDays, forKey: Self.retentionKey)
        }
    }

    var cacheCapMB: Int {
        didSet {
            cacheCapMB = max(0, min(2048, cacheCapMB))
            defaults.set(cacheCapMB, forKey: Self.cacheCapKey)
        }
    }

    var cacheEnabled: Bool {
        didSet { defaults.set(cacheEnabled, forKey: Self.enableCacheKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Pull stored values; substitute sensible defaults when the
        // user has never visited Settings before.
        let storedRetention = defaults.integer(forKey: Self.retentionKey)
        self.retentionDays = storedRetention > 0 ? storedRetention : 30
        let storedCap = defaults.integer(forKey: Self.cacheCapKey)
        self.cacheCapMB = storedCap > 0 ? storedCap : 100
        if defaults.object(forKey: Self.enableCacheKey) == nil {
            self.cacheEnabled = true
        } else {
            self.cacheEnabled = defaults.bool(forKey: Self.enableCacheKey)
        }
    }

    /// Convenience byte cap used by `TrashCoordinator`.
    var cacheCapBytes: Int64 {
        Int64(cacheCapMB) * 1024 * 1024
    }
}
