//
//  FinderWriteAccess.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 05.11.26.
//

import Foundation

/// Until when mounted buckets accept changes made in Finder, kept in
/// the App Group defaults. The host writes it each time it derives the
/// Pro entitlement; the File Provider extension checks it before every
/// create, change and delete.
///
/// A trial grant carries its end, so mounts turn read-only when the
/// trial ends even if the app is not running. A lapsed entitlement
/// makes mounts read-only instead of removing them: removing a domain
/// would drop Finder changes not uploaded yet. Until the host has
/// written a value, mounts stay writable, so an update does not lock a
/// Pro user out before the app has run.
public struct FinderWriteAccess: Sendable {
    private let suiteName: String

    public init(suiteName: String) {
        self.suiteName = suiteName
    }

    /// The setting shared by host and extension.
    public static let appGroup = FinderWriteAccess(suiteName: AppEnvironment.appGroupIdentifier)

    public func allowsWrites(at now: Date) -> Bool {
        guard let writableUntil = defaults?.object(forKey: Self.key) as? Date else { return true }
        return now < writableUntil
    }

    /// `.distantFuture` for Pro, the trial end for a trial,
    /// `.distantPast` once locked. Only the host writes.
    public func allowWrites(until writableUntil: Date) {
        defaults?.set(writableUntil, forKey: Self.key)
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    private static let key = "finderWriteAccess.writableUntil"
}
