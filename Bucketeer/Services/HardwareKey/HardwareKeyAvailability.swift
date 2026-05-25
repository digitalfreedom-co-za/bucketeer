//
//  HardwareKeyAvailability.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import CryptoTokenKit
import Observation

/// One discovered CryptoTokenKit slot — typically a YubiKey, PIV
/// smartcard, or any USB CCID reader currently plugged in.
/// Phase 13.16. Surfaced read-only in Settings → Security so the
/// user can verify their hardware is recognised before flipping the
/// "Hardware key unlock" toggle.
struct HardwareKeySlot: Identifiable, Hashable, Sendable {
    /// The slot name returned by `TKSmartCardSlotManager`. Stable
    /// per-port, so it's good as an identifier.
    let id: String
    let displayName: String
    /// `true` when a card is currently inserted into the slot.
    let cardPresent: Bool
}

/// Observable monitor that publishes the current list of detected
/// smartcard slots. Phase 13.16.
///
/// Implementation note: `TKSmartCardSlotManager` exposes a
/// KVO-observable `slotNames` array. We poll it on a 2-second timer
/// while the Settings view is on screen. CryptoTokenKit is permissive
/// enough that polling has no measurable cost.
@MainActor
@Observable
final class HardwareKeyAvailability {
    var slots: [HardwareKeySlot] = []
    /// `true` when at least one CCID-class reader is attached, even
    /// if no card is currently inserted. Useful for the UI to say
    /// "reader detected — insert your YubiKey".
    var hasReader: Bool { !slots.isEmpty }
    /// `true` when at least one slot has a card / token inserted.
    var hasInsertedToken: Bool { slots.contains { $0.cardPresent } }

    private var pollTask: Task<Void, Never>?

    // No deinit cancel — `pollTask` is main-actor-isolated and
    // can't be touched from `deinit`. The view that owns this
    // availability calls `stopMonitoring()` from `.onDisappear`,
    // which covers the live cancellation path. A leaked task that
    // outlives the instance simply self-completes when its weak
    // self goes away.

    /// Refresh the slot list once. Cheap — safe to call from a view
    /// `.task { }` modifier.
    func refresh() async {
        let manager = TKSmartCardSlotManager.default
        let names = manager?.slotNames ?? []
        var next: [HardwareKeySlot] = []
        for name in names {
            // `getSlot(withName:)` resolves the actual slot handle
            // so we can ask whether a card is present. Returns nil
            // when the slot was unplugged between names lookup and
            // resolve.
            // Resume with a plain Bool to avoid passing the non-Sendable
            // TKSmartCardSlot reference across the continuation boundary
            // (Swift 6 strict concurrency requirement).
            let present: Bool
            if let mgr = manager {
                present = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                    mgr.getSlot(withName: name) { slot in
                        cont.resume(returning: slot?.state == .validCard)
                    }
                }
            } else {
                present = false
            }
            next.append(
                HardwareKeySlot(id: name, displayName: name, cardPresent: present)
            )
        }
        self.slots = next
    }

    /// Begin a poll loop while the view is alive. Cancelled when
    /// `stopMonitoring()` is called.
    func startMonitoring() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
    }
}
