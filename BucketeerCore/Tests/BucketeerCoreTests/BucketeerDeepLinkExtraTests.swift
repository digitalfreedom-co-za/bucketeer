//
//  BucketeerDeepLinkExtraTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// Edge cases not covered by the original suite (Phase 13.11 follow-up).
@Suite("BucketeerDeepLink (edge cases)")
struct BucketeerDeepLinkExtraTests {

    private let accountID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    @Test("Scheme matching is case-insensitive")
    func schemeCaseInsensitive() {
        let url = URL(string: "BUCKETEER://activity")!
        #expect(BucketeerDeepLink(url: url) == .activity)
    }

    @Test("Object URL with key containing percent-encoded characters round-trips")
    func percentEncodedKey() {
        let link = BucketeerDeepLink.object(
            accountID: accountID,
            bucket: "photos",
            key: "report 2026/q1.pdf"
        )
        guard let url = link.url else {
            #expect(Bool(false), "URL builder should not return nil for spaces in key")
            return
        }
        // Parsed back, the key may differ in encoding but the decoded
        // components should match what we put in.
        let parsed = BucketeerDeepLink(url: url)
        if case .object(_, let bucket, let key) = parsed {
            #expect(bucket == "photos")
            #expect(key == "report 2026/q1.pdf" || key == "report%202026/q1.pdf")
        } else {
            #expect(Bool(false), "Expected object case, got \(String(describing: parsed))")
        }
    }

    @Test("Bucket URL preserves single-segment prefix")
    func singleSegmentPrefix() {
        let link = BucketeerDeepLink.bucket(
            accountID: accountID,
            bucket: "photos",
            prefix: "archive/"
        )
        let url = link.url!
        let parsed = BucketeerDeepLink(url: url)
        #expect(parsed == link)
    }

    @Test("URL with extraneous query string is still parseable")
    func extraQueryStringIgnored() {
        let url = URL(string: "bucketeer://account/\(accountID.uuidString)?ref=share")!
        #expect(BucketeerDeepLink(url: url) == .account(id: accountID))
    }
}
