//
//  BandwidthSettings.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import Observation
import BucketeerCore

/// Owns the user-facing bandwidth cap and pushes changes into the
/// shared `BandwidthLimiter` actor. Persists to UserDefaults so the
/// cap survives app restarts. Phase 13.2.
///
/// The user picks one of a small set of presets (or "Unlimited") plus
/// a custom MB/s value. The view binds to `selectedPreset` and
/// `customMegabytesPerSecond`; this class projects those into the raw
/// `bytesPerSecond` value that gets handed to the limiter.
@MainActor
@Observable
final class BandwidthSettings {
    enum Preset: String, CaseIterable, Identifiable {
        case unlimited
        case kb256
        case mb1
        case mb5
        case mb25
        case custom

        var id: String { rawValue }

        var labelKey: String {
            switch self {
            case .unlimited: return "bandwidth.preset.unlimited"
            case .kb256:     return "bandwidth.preset.256kb"
            case .mb1:       return "bandwidth.preset.1mb"
            case .mb5:       return "bandwidth.preset.5mb"
            case .mb25:      return "bandwidth.preset.25mb"
            case .custom:    return "bandwidth.preset.custom"
            }
        }

        /// Bytes-per-second for the preset; `nil` for `.custom`,
        /// which reads the user-entered value separately.
        var bytesPerSecond: Int? {
            switch self {
            case .unlimited: return 0
            case .kb256:     return 256 * 1024
            case .mb1:       return 1 * 1024 * 1024
            case .mb5:       return 5 * 1024 * 1024
            case .mb25:      return 25 * 1024 * 1024
            case .custom:    return nil
            }
        }
    }

    /// Persisted under this key. Single Int (bytes per second). `0`
    /// is unlimited.
    private static let storageKey = "bandwidth.limit.bytesPerSecond"

    private let defaults: UserDefaults
    private let limiter: BandwidthLimiter

    /// User-selected preset. Calling the setter also flushes the new
    /// effective cap into the limiter + UserDefaults.
    var selectedPreset: Preset {
        didSet { applyChange() }
    }

    /// Custom MB/s value — only consulted when `selectedPreset ==
    /// .custom`. Range-clamped to 1...512 to keep the slider sane.
    var customMegabytesPerSecond: Int {
        didSet {
            customMegabytesPerSecond = max(1, min(512, customMegabytesPerSecond))
            if selectedPreset == .custom { applyChange() }
        }
    }

    init(limiter: BandwidthLimiter, defaults: UserDefaults = .standard) {
        self.limiter = limiter
        self.defaults = defaults
        let stored = defaults.integer(forKey: Self.storageKey)
        let normalised = max(0, stored)
        // Pick the preset that matches the stored value; otherwise
        // fall back to .custom and seed the MB/s field.
        if normalised == 0 {
            self.selectedPreset = .unlimited
            self.customMegabytesPerSecond = 10
        } else if let preset = Preset.allCases.first(where: { $0.bytesPerSecond == normalised }) {
            self.selectedPreset = preset
            self.customMegabytesPerSecond = max(1, normalised / (1024 * 1024))
        } else {
            self.selectedPreset = .custom
            self.customMegabytesPerSecond = max(1, normalised / (1024 * 1024))
        }
        // Push the stored value into the limiter on launch.
        let bytes = effectiveBytesPerSecond
        Task { [limiter] in await limiter.setLimit(bytesPerSecond: bytes) }
    }

    /// Resolve the configured preset + custom value into a concrete
    /// bytes-per-second cap.
    var effectiveBytesPerSecond: Int {
        if let preset = selectedPreset.bytesPerSecond { return preset }
        return customMegabytesPerSecond * 1024 * 1024
    }

    private func applyChange() {
        let bytes = effectiveBytesPerSecond
        defaults.set(bytes, forKey: Self.storageKey)
        Task { [limiter] in await limiter.setLimit(bytesPerSecond: bytes) }
    }
}
