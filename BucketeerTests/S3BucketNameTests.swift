//
//  S3BucketNameTests.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 12.11.26.
//

import XCTest

/// A manually entered bucket must follow the S3 naming rules, so a
/// typo cannot register a key for a bucket that cannot exist.
final class S3BucketNameTests: XCTestCase {
    func testAcceptsOnlyNamesFollowingTheS3Rules() {
        for name in ["abc", "photos-2026", "backup.eu.1", "0bucket9", String(repeating: "a", count: 63)] {
            XCTAssertTrue(S3BucketName.isValid(name), name)
        }
        for name in ["", "ab", String(repeating: "a", count: 64), "Photos", "-photos", "photos-",
                     ".photos", "photos.", "photo_s", "photo s", "fotós"] {
            XCTAssertFalse(S3BucketName.isValid(name), name)
        }
    }
}
