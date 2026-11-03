//
//  ScreenshotDemoLaunch.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

#if DEBUG
import Foundation
import BucketeerCore

/// The App Store screenshot screens the demo mode opens without clicks.
enum ScreenshotDemoScreen: String, Sendable {
    case browser = "01_browser"
    case addAccount = "02_add_account"
    case dashboard = "03_dashboard"
    case versions = "04_versions"
    case metadata = "05_metadata"
    case sync = "06_sync"
    case activity = "07_activity"
    case encryption = "08_encryption"
    case pro = "09_pro"
    /// Review-only shot of the paywall with the local StoreKit products.
    case paywall
}

/// Launch options of the screenshot demo mode. Debug builds only, and
/// only in the QA copy of the app: its own bundle id gives it its own
/// sandbox container, so the demo can never see the user's accounts.
struct ScreenshotDemoLaunch: Equatable {
    static let qaBundleIdentifier = "za.co.digitalfreedom.Bucketeer.qa"

    let screen: ScreenshotDemoScreen?
    let seedPath: String?

    /// `nil` unless the launch flag is set *and* the bundle is the QA copy.
    static func parse(arguments: [String], bundleIdentifier: String?) -> ScreenshotDemoLaunch? {
        guard bundleIdentifier == qaBundleIdentifier,
              value(after: "-BucketeerScreenshotDemo", in: arguments) == "YES"
        else { return nil }
        return ScreenshotDemoLaunch(
            screen: value(after: "-BucketeerDemoScreen", in: arguments).flatMap(ScreenshotDemoScreen.init(rawValue:)),
            seedPath: value(after: "-BucketeerDemoSeed", in: arguments)
        )
    }

    static var current: ScreenshotDemoLaunch? {
        parse(arguments: ProcessInfo.processInfo.arguments, bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    /// In-memory stores and Keychain, no launch work. The store shots
    /// pin a running trial; the paywall derives its state from StoreKit
    /// so the products and the trial offer load.
    var containerConfiguration: AppContainer.Configuration {
        AppContainer.Configuration(
            stores: .inMemory,
            keychainStore: InMemoryKeychain(),
            entitlementState: screen == .paywall ? nil : .trial(daysRemaining: ProAccessResolver.trialLengthDays),
            startsBackgroundWork: false
        )
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
#endif
