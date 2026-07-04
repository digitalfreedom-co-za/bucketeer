//
//  TrialBookkeeping.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation

/// Pure trial-state computation lifted out of the host's
/// `EntitlementManager`. Keeps the StoreKit-tied behaviour in the host
/// and lets us regression-test the future-date clamp + consumed marker
/// (Codex review #8 mitigation) without standing up an Observable
/// model in a UI test target.
///
/// Storage is abstracted via `TrialDefaults` so tests can swap in an
/// in-memory backing without touching the real user defaults DB.
public protocol TrialDefaults: Sendable {
    func date(forKey key: String) -> Date?
    func setDate(_ value: Date, forKey key: String)
    func bool(forKey key: String) -> Bool
    func setBool(_ value: Bool, forKey key: String)
}

/// Production conformance — defers to `UserDefaults.standard`.
public struct UserDefaultsTrialStore: TrialDefaults {
    public init() {}

    public func date(forKey key: String) -> Date? {
        UserDefaults.standard.object(forKey: key) as? Date
    }

    public func setDate(_ value: Date, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    public func bool(forKey key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    public func setBool(_ value: Bool, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

/// Pure trial state. Holds the two preference keys + duration constant
/// and exposes deterministic `start(now:)` and `daysRemaining(now:)`
/// for a given clock reading. The host wraps this in an @Observable
/// state machine; tests construct it with an in-memory store.
public struct TrialBookkeeping: Sendable {
    public static let trialStartKey = "bucketeer.trial.start"
    public static let trialConsumedKey = "bucketeer.trial.consumed"
    /// Highest clock reading ever observed — defeats backward clock
    /// rollbacks mid-trial (setting the Mac's clock back at day 13
    /// used to recover already-consumed days).
    public static let trialHighWaterKey = "bucketeer.trial.highwater"
    public static let defaultTrialLengthSeconds: TimeInterval = 14 * 24 * 60 * 60

    public let store: any TrialDefaults
    public let trialLengthSeconds: TimeInterval

    public init(
        store: any TrialDefaults = UserDefaultsTrialStore(),
        trialLengthSeconds: TimeInterval = TrialBookkeeping.defaultTrialLengthSeconds
    ) {
        self.store = store
        self.trialLengthSeconds = trialLengthSeconds
    }

    /// Mark the trial as started if it isn't already and hasn't been
    /// consumed. Idempotent — the user's existing trial-start date
    /// always wins over the supplied `now` for the trial-start record.
    public func start(now: Date = Date()) {
        // Sticky consumed marker — never restart a trial that has
        // already expired, even when the user deletes the start key.
        if store.bool(forKey: Self.trialConsumedKey) { return }
        if store.date(forKey: Self.trialStartKey) == nil {
            store.setDate(now, forKey: Self.trialStartKey)
        }
    }

    /// Days remaining in the trial as displayed in the UI. Returns
    /// `nil` once the trial has expired (and writes the consumed
    /// marker so future calls short-circuit).
    public func daysRemaining(now: Date = Date()) -> Int? {
        if store.bool(forKey: Self.trialConsumedKey) { return nil }

        // High-watermark: never let the effective clock regress. A
        // backward system-clock change mid-trial keeps the largest
        // date ever seen, so elapsed time cannot shrink.
        let watermark = store.date(forKey: Self.trialHighWaterKey)
        let effectiveNow = max(now, watermark ?? now)
        if watermark == nil || effectiveNow > watermark! {
            store.setDate(effectiveNow, forKey: Self.trialHighWaterKey)
        }

        // Clamp future start dates — flipping the system clock or
        // editing the plist to a date in the future used to extend
        // the trial. Treat anything in the future as "now" and rewrite
        // the persisted start so subsequent calls see a clean baseline.
        let rawStart = store.date(forKey: Self.trialStartKey)
        let start: Date
        if let rawStart, rawStart <= effectiveNow {
            start = rawStart
        } else {
            start = effectiveNow
            store.setDate(effectiveNow, forKey: Self.trialStartKey)
        }

        let elapsed = effectiveNow.timeIntervalSince(start)
        let remaining = trialLengthSeconds - elapsed
        guard remaining > 0 else {
            store.setBool(true, forKey: Self.trialConsumedKey)
            return nil
        }
        return Int(ceil(remaining / 86_400))
    }
}
