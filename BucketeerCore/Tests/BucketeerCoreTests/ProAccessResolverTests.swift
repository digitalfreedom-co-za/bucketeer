//
//  ProAccessResolverTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

@Suite("ProAccessResolver")
struct ProAccessResolverTests {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let day: TimeInterval = 86_400

    private func trial(at date: Date, revoked: Date? = nil) -> StoreTransactionRecord {
        StoreTransactionRecord(
            productID: ProductIDs.trial,
            originalPurchaseDate: date,
            revocationDate: revoked
        )
    }

    private func lifetime(at date: Date, revoked: Date? = nil) -> StoreTransactionRecord {
        StoreTransactionRecord(
            productID: ProductIDs.lifetime,
            originalPurchaseDate: date,
            revocationDate: revoked
        )
    }

    @Test("No transactions: the trial can be started")
    func noTransactions() {
        #expect(ProAccessResolver.resolve([], now: t0) == .trialAvailable)
    }

    @Test("Trial runs for 14 days from the original purchase date")
    func trialRunsFourteenDays() {
        let access = ProAccessResolver.resolve([trial(at: t0)], now: t0.addingTimeInterval(3 * day))
        #expect(access == .trial(endsAt: t0.addingTimeInterval(14 * day)))
    }

    @Test("Trial is over at exactly 14 days")
    func trialEndsAtFourteenDays() {
        let access = ProAccessResolver.resolve([trial(at: t0)], now: t0.addingTimeInterval(14 * day))
        #expect(access == .trialEnded)
    }

    @Test("Lifetime wins over a running trial")
    func lifetimeWinsOverRunningTrial() {
        let access = ProAccessResolver.resolve(
            [trial(at: t0), lifetime(at: t0.addingTimeInterval(day))],
            now: t0.addingTimeInterval(2 * day)
        )
        #expect(access == .lifetime)
    }

    @Test("Lifetime wins over an expired trial")
    func lifetimeWinsOverExpiredTrial() {
        let access = ProAccessResolver.resolve(
            [lifetime(at: t0.addingTimeInterval(20 * day)), trial(at: t0)],
            now: t0.addingTimeInterval(30 * day)
        )
        #expect(access == .lifetime)
    }

    @Test("A revoked lifetime purchase does not unlock Pro")
    func revokedLifetimeIgnored() {
        let access = ProAccessResolver.resolve(
            [lifetime(at: t0, revoked: t0.addingTimeInterval(day))],
            now: t0.addingTimeInterval(2 * day)
        )
        #expect(access == .trialAvailable)
    }

    @Test("A revoked trial does not unlock Pro and cannot be restarted")
    func revokedTrialIsEnded() {
        let access = ProAccessResolver.resolve(
            [trial(at: t0, revoked: t0.addingTimeInterval(day))],
            now: t0.addingTimeInterval(2 * day)
        )
        #expect(access == .trialEnded)
    }

    @Test("The earliest trial transaction sets the start")
    func earliestTrialWins() {
        let access = ProAccessResolver.resolve(
            [trial(at: t0.addingTimeInterval(10 * day)), trial(at: t0)],
            now: t0.addingTimeInterval(13 * day)
        )
        #expect(access == .trial(endsAt: t0.addingTimeInterval(14 * day)))
    }

    @Test("Unknown products are ignored")
    func unknownProductsIgnored() {
        let other = StoreTransactionRecord(productID: "other", originalPurchaseDate: t0, revocationDate: nil)
        #expect(ProAccessResolver.resolve([other], now: t0) == .trialAvailable)
    }

    @Test("The trial end is anchored to the purchase date, not the local clock")
    func trialEndAnchoredToPurchaseDate() {
        let start = t0.addingTimeInterval(day)
        let access = ProAccessResolver.resolve([trial(at: start)], now: t0)
        #expect(access == .trial(endsAt: start.addingTimeInterval(14 * day)))
    }

    @Test("Days remaining rounds partial days up")
    func daysRemainingRoundsUp() {
        let endsAt = t0.addingTimeInterval(14 * day)
        #expect(ProAccessResolver.daysRemaining(until: endsAt, now: t0) == 14)
        #expect(ProAccessResolver.daysRemaining(until: endsAt, now: endsAt.addingTimeInterval(-3_600)) == 1)
        #expect(ProAccessResolver.daysRemaining(until: endsAt, now: endsAt) == 0)
    }
}
