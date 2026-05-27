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
            // Codex audit R2 (medium): CryptoTokenKit can fail to
            // invoke the callback at all if the driver crashed or
            // the reader was hot-unplugged. Without a timeout the
            // continuation hangs `refresh()` and the polling loop
            // with it. 500 ms is generous for a local USB call.
            let present: Bool
            if let mgr = manager {
                present = await Self.cardPresent(in: mgr, name: name)
            } else {
                present = false
            }
            next.append(
                HardwareKeySlot(id: name, displayName: name, cardPresent: present)
            )
        }
        self.slots = next
    }

    /// Race the slot-resolve callback against a 500 ms timeout via
    /// `TaskGroup` so a stuck driver can't wedge the UI.
    ///
    /// `TKSmartCardSlotManager` is a non-`Sendable` ObjC class, so it
    /// cannot be captured directly by a `@Sendable` `addTask` closure.
    /// We box it in a `@unchecked Sendable` wrapper — the CryptoTokenKit
    /// manager is a thread-safe system singleton designed for concurrent
    /// use; the wrapper is a known-safe suppression of the Swift 6 check.
    private static func cardPresent(in mgr: TKSmartCardSlotManager, name: String) async -> Bool {
        struct SendableMgr: @unchecked Sendable {
            let value: TKSmartCardSlotManager
        }
        let box = SendableMgr(value: mgr)
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                    box.value.getSlot(withName: name) { slot in
                        cont.resume(returning: slot?.state == .validCard)
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 500_000_000)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    /// Begin a poll loop while the view is alive. Cancelled when
    /// `stopMonitoring()` is called.
    func startMonitoring() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                // Codex audit R2 (medium): break the loop when the
                // owning availability instance is gone so the poll
                // task self-terminates rather than sleeping forever
                // against a nil weak-self.
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
    }
}
