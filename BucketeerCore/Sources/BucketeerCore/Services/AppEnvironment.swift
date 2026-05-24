//
//  AppEnvironment.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation

/// Static configuration shared between host app, future File Provider
/// extension, and any helper. Lives here as compile-time constants —
/// these values match what's encoded in `Info.plist` and `.entitlements`.
public enum AppEnvironment {
    /// App Group container shared with the File Provider extension.
    /// Backs the SwiftData store so the extension can read account
    /// metadata.
    public static let appGroupIdentifier = "group.za.co.digitalfreedom.bucketeer"

    /// `kSecAttrService` used for every credential entry.
    public static let keychainService = "za.co.digitalfreedom.bucketeer"

    /// Apple Developer team identifier.
    public static let teamIdentifier = "7TSZJCJY88"

    /// `kSecAttrAccessGroup` value. The team prefix is required for
    /// Keychain to recognise the group at runtime.
    public static let keychainAccessGroup = "\(teamIdentifier).za.co.digitalfreedom.bucketeer.shared"

    /// Filename of the SwiftData store inside the App Group container.
    public static let swiftDataStoreFileName = "Bucketeer.store"

    /// Filename of the *host-only* activity log store. Kept out of the
    /// App Group container on purpose — the File Provider extension
    /// has no use for audit history and would needlessly load the
    /// schema otherwise. Lives in the sandbox Application Support
    /// directory.
    public static let activityStoreFileName = "BucketeerActivity.store"
}
