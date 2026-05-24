//
//  BandwidthLimiterTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// Exercises the token-bucket rate limiter from Phase 13.2. Sleep
/// timing on macOS isn't sub-millisecond accurate so every "should
/// take roughly N seconds" assertion uses a generous lower bound and
/// just checks the limiter is *at least* honouring the budget.
@Suite("BandwidthLimiter")
struct BandwidthLimiterTests {

    @Test("Limit of zero is unlimited — every call returns instantly")
    func unlimited() async {
        let limiter = BandwidthLimiter(bytesPerSecond: 0)
        let start = Date()
        await limiter.consume(bytes: 100_000_000)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.05, "Expected near-instant return, took \(elapsed)s")
    }

    @Test("A single request smaller than the burst returns immediately")
    func underBurst() async {
        let limiter = BandwidthLimiter(bytesPerSecond: 1_000_000)
        let start = Date()
        await limiter.consume(bytes: 100)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.05)
    }

    @Test("A request bigger than the bucket sleeps for at least the deficit")
    func deficitSleeps() async {
        // 1 KB/s; ask for 4 KB — bucket starts full at 1 KB so we
        // expect ~3 seconds of sleep, allow generous slack.
        let limiter = BandwidthLimiter(bytesPerSecond: 1_024)
        let start = Date()
        await limiter.consume(bytes: 4_096)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed >= 2.5, "Expected at least 2.5s, took \(elapsed)s")
        #expect(elapsed < 6.0, "Sanity upper bound — took \(elapsed)s")
    }

    @Test("setLimit(0) mid-flight stops further charging")
    func toggleToUnlimited() async {
        let limiter = BandwidthLimiter(bytesPerSecond: 10)
        await limiter.consume(bytes: 5)
        await limiter.setLimit(bytesPerSecond: 0)
        let start = Date()
        await limiter.consume(bytes: 10_000)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.05)
    }

    @Test("currentLimit reflects the most recent setLimit call")
    func currentLimitReflectsSetter() async {
        let limiter = BandwidthLimiter(bytesPerSecond: 2_048)
        var snapshot = await limiter.currentLimit
        #expect(snapshot == 2_048)
        await limiter.setLimit(bytesPerSecond: 4_096)
        snapshot = await limiter.currentLimit
        #expect(snapshot == 4_096)
    }
}
