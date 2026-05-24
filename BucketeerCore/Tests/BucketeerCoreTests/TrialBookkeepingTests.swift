//
//  TrialBookkeepingTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import Testing
@testable import BucketeerCore

@Suite("TrialBookkeeping")
struct TrialBookkeepingTests {

    /// In-memory `TrialDefaults` for hermetic tests — avoids touching
    /// the host machine's actual UserDefaults DB.
    final class MemoryStore: TrialDefaults, @unchecked Sendable {
        private var dates: [String: Date] = [:]
        private var bools: [String: Bool] = [:]
        func date(forKey key: String) -> Date? { dates[key] }
        func setDate(_ value: Date, forKey key: String) { dates[key] = value }
        func bool(forKey key: String) -> Bool { bools[key] ?? false }
        func setBool(_ value: Bool, forKey key: String) { bools[key] = value }
    }

    private func bookkeeping(
        trialLength: TimeInterval = TrialBookkeeping.defaultTrialLengthSeconds
    ) -> (TrialBookkeeping, MemoryStore) {
        let store = MemoryStore()
        return (TrialBookkeeping(store: store, trialLengthSeconds: trialLength), store)
    }

    // MARK: - Fresh trial

    @Test("Fresh state: start() records now as trial-start")
    func freshStartRecordsNow() {
        let (book, store) = bookkeeping()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        book.start(now: t0)
        #expect(store.date(forKey: TrialBookkeeping.trialStartKey) == t0)
    }

    @Test("Fresh state: 14 days remaining immediately after start")
    func freshDaysRemaining() {
        let (book, _) = bookkeeping()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        book.start(now: t0)
        #expect(book.daysRemaining(now: t0) == 14)
    }

    @Test("Mid-trial: 7 days remaining after 7 days elapsed")
    func midTrialDaysRemaining() {
        let (book, _) = bookkeeping()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        book.start(now: t0)
        let mid = t0.addingTimeInterval(7 * 86_400)
        #expect(book.daysRemaining(now: mid) == 7)
    }

    // MARK: - Expiry + consumed marker

    @Test("Trial expires after 14 days — daysRemaining returns nil")
    func trialExpires() {
        let (book, _) = bookkeeping()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        book.start(now: t0)
        let past = t0.addingTimeInterval(15 * 86_400)
        #expect(book.daysRemaining(now: past) == nil)
    }

    @Test("Expiry writes the sticky consumed marker — short-circuits future polls")
    func expirySetsConsumedMarker() {
        let (book, store) = bookkeeping()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        book.start(now: t0)
        _ = book.daysRemaining(now: t0.addingTimeInterval(15 * 86_400))
        #expect(store.bool(forKey: TrialBookkeeping.trialConsumedKey) == true)
    }

    @Test("Consumed marker survives deleting the trial-start key — Codex review #8 mitigation")
    func consumedMarkerSurvivesStartDeletion() {
        let (book, store) = bookkeeping()
        // Simulate trial expiry, then user deletes the start key
        store.setBool(true, forKey: TrialBookkeeping.trialConsumedKey)
        let later = Date(timeIntervalSince1970: 2_000_000)
        // start() now does nothing — the consumed marker keeps the
        // trial closed even though the start date is missing
        book.start(now: later)
        #expect(store.date(forKey: TrialBookkeeping.trialStartKey) == nil)
        #expect(book.daysRemaining(now: later) == nil)
    }

    // MARK: - Future-date clamp

    @Test("Future trial-start dates are clamped to now — Codex review #8 mitigation")
    func futureStartIsClamped() {
        let (book, store) = bookkeeping()
        let now = Date(timeIntervalSince1970: 1_000_000)
        // User edits the plist to put the trial-start 100 days in the
        // future. The bookkeeping must rewrite it to `now` and still
        // grant exactly the configured trial length, never more.
        let future = now.addingTimeInterval(100 * 86_400)
        store.setDate(future, forKey: TrialBookkeeping.trialStartKey)
        #expect(book.daysRemaining(now: now) == 14)
        // The persisted start is now clamped — no future-date residue
        #expect(store.date(forKey: TrialBookkeeping.trialStartKey) == now)
    }

    @Test("start() never overwrites an existing valid trial-start")
    func startIsIdempotent() {
        let (book, store) = bookkeeping()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        book.start(now: t0)
        // Calling start again at a later time must not move the trial-start
        book.start(now: t0.addingTimeInterval(86_400))
        #expect(store.date(forKey: TrialBookkeeping.trialStartKey) == t0)
    }

    // MARK: - Custom trial length

    @Test("Trial length is configurable for tests")
    func customTrialLength() {
        let (book, _) = bookkeeping(trialLength: 60)  // 60-second trial
        let t0 = Date(timeIntervalSince1970: 0)
        book.start(now: t0)
        #expect(book.daysRemaining(now: t0) == 1)              // <1 day → ceil to 1
        #expect(book.daysRemaining(now: t0.addingTimeInterval(30)) == 1)
        #expect(book.daysRemaining(now: t0.addingTimeInterval(60)) == nil)
    }

    // MARK: - Edge cases

    @Test("daysRemaining always rounds up — partial days surface as full")
    func roundsUpToCeiling() {
        let (book, _) = bookkeeping()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        book.start(now: t0)
        // 13 days 23 hours elapsed → 1 hour remaining → ceil to 1 day
        let almost = t0.addingTimeInterval(14 * 86_400 - 3_600)
        #expect(book.daysRemaining(now: almost) == 1)
    }

    @Test("daysRemaining: nil persists between calls once the trial is consumed")
    func consumedNeverRevives() {
        let (book, _) = bookkeeping()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        book.start(now: t0)
        _ = book.daysRemaining(now: t0.addingTimeInterval(15 * 86_400))
        // Even when the caller passes a date back inside the original
        // trial window, the consumed marker keeps the trial closed.
        #expect(book.daysRemaining(now: t0) == nil)
    }
}
