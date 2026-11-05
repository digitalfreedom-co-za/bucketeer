//
//  FinderWriteAccess.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 05.11.26.
//

import Foundation

/// Whether mounted buckets accept changes made in Finder, kept in the
/// App Group defaults. The host writes it each time it derives the Pro
/// entitlement; the File Provider extension reads it before every
/// create, change and delete.
///
/// A lapsed entitlement makes mounts read-only instead of removing
/// them: removing a domain would drop Finder changes not uploaded yet.
/// Until the host has written a value, mounts stay writable, so an
/// update does not lock a Pro user out before the app has run.
public struct FinderWriteAccess: Sendable {
    private let suiteName: String

    public init(suiteName: String) {
        self.suiteName = suiteName
    }

    /// The setting shared by host and extension.
    public static let appGroup = FinderWriteAccess(suiteName: AppEnvironment.appGroupIdentifier)

    public var isReadOnly: Bool {
        defaults?.bool(forKey: Self.key) ?? false
    }

    /// Only the host writes.
    public func setReadOnly(_ readOnly: Bool) {
        defaults?.set(readOnly, forKey: Self.key)
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    private static let key = "finderWriteAccess.readOnly"
}
