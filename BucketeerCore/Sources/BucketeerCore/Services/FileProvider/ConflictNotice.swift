//
//  ConflictNotice.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import UserNotifications

/// Tells the user, in Notification Center, that a Finder change met a
/// newer or colliding server object and both versions were kept.
/// Posted from the File Provider extension; the host asks for
/// (provisional, prompt-free) permission at launch.
public enum ConflictNotice {

    public enum Kind: Sendable {
        /// The change was saved under a conflict-copy name.
        case conflictCopy
        /// A rename was not applied because the server object changed.
        case renameKeptServerVersion
        /// A delete was refused because the server object changed.
        case deletionRefused
    }

    /// Provisional: notices land quietly in Notification Center without
    /// an authorization prompt.
    public static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.provisional, .alert]) { _, _ in }
    }

    public static func post(_ kind: Kind, fileName: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "conflict.notice.title", bundle: .bucketeerApp)
        content.body = body(kind, fileName: fileName)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    static func body(_ kind: Kind, fileName: String) -> String {
        switch kind {
        case .conflictCopy:
            return String(localized: "conflict.notice.copy \(fileName)", bundle: .bucketeerApp)
        case .renameKeptServerVersion:
            return String(localized: "conflict.notice.rename \(fileName)", bundle: .bucketeerApp)
        case .deletionRefused:
            return String(localized: "conflict.notice.delete \(fileName)", bundle: .bucketeerApp)
        }
    }
}

extension Bundle {
    /// The app bundle, also from inside the File Provider extension
    /// (`Bucketeer.app/Contents/PlugIns/<extension>.appex`), whose
    /// string catalog the extension does not carry itself.
    static var bucketeerApp: Bundle {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "appex" else { return .main }
        let app = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return Bundle(url: app) ?? .main
    }
}
