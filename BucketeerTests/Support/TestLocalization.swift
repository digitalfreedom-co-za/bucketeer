//
//  TestLocalization.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation
import ObjectiveC

/// The test bundle has no host app: `Bundle.main` is the xctest runner,
/// which has no string catalog, so views would render raw keys. This
/// points `Bundle.main` at the test bundle (it compiles the app's
/// Localizable.xcstrings) and pins English in the volatile argument
/// domain, which is never written to disk.
enum TestLocalization {
    @MainActor static func install() {
        guard !installed else { return }
        installed = true
        UserDefaults.standard.setVolatileDomain(["AppleLanguages": ["en"]], forName: UserDefaults.argumentDomain)
        guard let original = class_getClassMethod(Bundle.self, #selector(getter: Bundle.main)),
              let replacement = class_getClassMethod(Bundle.self, #selector(getter: Bundle.bucketeerTestBundle))
        else { return }
        method_exchangeImplementations(original, replacement)
    }

    @MainActor private static var installed = false
}

private final class TestBundleMarker {}

extension Bundle {
    @objc fileprivate class var bucketeerTestBundle: Bundle { Bundle(for: TestBundleMarker.self) }
}
