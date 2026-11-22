//
//  TurkishLocalizationTests.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 22.11.26.
//

import XCTest

/// Turkish is an App Store locale (decision log #14), so the catalog
/// must ship a tr localization instead of falling back to English.
final class TurkishLocalizationTests: XCTestCase {
    func testTurkishCatalogResolves() throws {
        let resources = Bundle(for: Self.self)
        let turkish = try XCTUnwrap(Bundle(path: XCTUnwrap(resources.path(forResource: "tr", ofType: "lproj"))))
        let locale = Locale(identifier: "tr")
        XCTAssertEqual(String(localized: "mount.error.refreshFailed", bundle: turkish, locale: locale),
                       "Bucketeer, Finder'da hangi bucket'ların bağlı olduğunu denetleyemedi. Yeniden denemek için Bucketeer'dan çık ve yeniden aç.")
        XCTAssertEqual(String(localized: "sidebar.section.sync", bundle: turkish, locale: locale), "Eşitleme")
        XCTAssertEqual(String(localized: "sync.summary.run \(12) \(3) \(14) \(2)", bundle: turkish, locale: locale),
                       "12 tamamlandı / 3 başarısız (2 kaynak silinemedi) / 14 planlandı")
    }
}
