//
//  AppEnvironment.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation

/// Static configuration shared between host app, future File Provider
/// extension, and any helper. Lives here as compile-time constants —
/// these values match what's encoded in `Info.plist` and `.entitlements`.
enum AppEnvironment {
    /// App Group container shared with the File Provider extension.
    /// Backs the SwiftData store so the extension can read account
    /// metadata.
    static let appGroupIdentifier = "group.za.co.digitalfreedom.s3-browser"

    /// `kSecAttrService` used for every credential entry.
    static let keychainService = "za.co.digitalfreedom.s3-browser"

    /// Apple Developer team identifier.
    static let teamIdentifier = "7TSZJCJY88"

    /// `kSecAttrAccessGroup` value. The team prefix is required for
    /// Keychain to recognise the group at runtime.
    static let keychainAccessGroup = "\(teamIdentifier).za.co.digitalfreedom.s3-browser.shared"

    /// Filename of the SwiftData store inside the App Group container.
    static let swiftDataStoreFileName = "S3Browser.store"
}
