//
//  ProAccessResolver.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation

/// App Store product identifiers for Bucketeer Pro.
public enum ProductIDs {
    /// Non-consumable, paid once.
    public static let lifetime = "za.co.digitalfreedom.bucketeer.pro.lifetime"
    /// Non-consumable at price Free. Its original purchase date starts
    /// the trial, so the trial survives reinstalls and is restored by
    /// Restore Purchases like any other purchase.
    public static let trial = "za.co.digitalfreedom.bucketeer.pro.trial"
}

/// The parts of a verified StoreKit transaction the resolver needs.
/// The host maps `StoreKit.Transaction` into this so the rules stay
/// testable without StoreKit.
public struct StoreTransactionRecord: Sendable, Equatable {
    public let productID: String
    public let originalPurchaseDate: Date
    public let revocationDate: Date?

    public init(productID: String, originalPurchaseDate: Date, revocationDate: Date?) {
        self.productID = productID
        self.originalPurchaseDate = originalPurchaseDate
        self.revocationDate = revocationDate
    }
}

public enum ProAccess: Equatable, Sendable {
    case lifetime
    case trial(endsAt: Date)
    case trialEnded
    case trialAvailable
}

/// Derives Pro access from the user's StoreKit transactions. Pure: the
/// same transactions and clock reading always give the same answer.
public enum ProAccessResolver {
    public static let trialLength: TimeInterval = 14 * 86_400
    public static let trialLengthDays = 14

    public static func resolve(_ transactions: [StoreTransactionRecord], now: Date) -> ProAccess {
        if transactions.contains(where: { $0.productID == ProductIDs.lifetime && $0.revocationDate == nil }) {
            return .lifetime
        }
        let trialTransactions = transactions.filter { $0.productID == ProductIDs.trial }
        guard !trialTransactions.isEmpty else { return .trialAvailable }
        // A refunded or revoked trial is used up; the product cannot be
        // claimed a second time.
        guard let start = trialTransactions
            .filter({ $0.revocationDate == nil })
            .map(\.originalPurchaseDate)
            .min()
        else { return .trialEnded }

        let endsAt = start.addingTimeInterval(trialLength)
        return now < endsAt ? .trial(endsAt: endsAt) : .trialEnded
    }

    /// Whole days left as shown in the UI; a partial day counts as one.
    public static func daysRemaining(until endsAt: Date, now: Date) -> Int {
        let seconds = endsAt.timeIntervalSince(now)
        guard seconds > 0 else { return 0 }
        return Int((seconds / 86_400).rounded(.up))
    }
}
