//
//  BucketeerDeepLinkTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import Testing
@testable import BucketeerCore

@Suite("BucketeerDeepLink")
struct BucketeerDeepLinkTests {

    private let accountID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let jobID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test("Account URL round-trips")
    func accountRoundTrip() {
        let link = BucketeerDeepLink.account(id: accountID)
        let url = link.url!
        #expect(url.absoluteString == "bucketeer://account/\(accountID.uuidString)")
        #expect(BucketeerDeepLink(url: url) == link)
    }

    @Test("Bucket URL with empty prefix round-trips")
    func bucketEmptyPrefix() {
        let link = BucketeerDeepLink.bucket(accountID: accountID, bucket: "photos", prefix: "")
        let url = link.url!
        let parsed = BucketeerDeepLink(url: url)
        #expect(parsed == link)
    }

    @Test("Bucket URL with multi-segment prefix round-trips")
    func bucketDeepPrefix() {
        let link = BucketeerDeepLink.bucket(
            accountID: accountID,
            bucket: "photos",
            prefix: "2026/05/"
        )
        let url = link.url!
        let parsed = BucketeerDeepLink(url: url)
        #expect(parsed == link)
    }

    @Test("Object URL preserves multi-segment keys")
    func objectDeepKey() {
        let link = BucketeerDeepLink.object(
            accountID: accountID,
            bucket: "photos",
            key: "2026/05/img.jpg"
        )
        let url = link.url!
        let parsed = BucketeerDeepLink(url: url)
        #expect(parsed == link)
    }

    @Test("Sync URL round-trips")
    func syncRoundTrip() {
        let link = BucketeerDeepLink.syncJob(id: jobID)
        #expect(BucketeerDeepLink(url: link.url!) == link)
    }

    @Test("Activity + trash hosts parse as singletons")
    func singletons() {
        #expect(BucketeerDeepLink(url: URL(string: "bucketeer://activity")!) == .activity)
        #expect(BucketeerDeepLink(url: URL(string: "bucketeer://trash")!) == .trash)
    }

    @Test("Unknown scheme returns nil")
    func unknownScheme() {
        #expect(BucketeerDeepLink(url: URL(string: "https://example.com/bucketeer/x")!) == nil)
    }

    @Test("Garbage account UUID is rejected")
    func badUUID() {
        #expect(BucketeerDeepLink(url: URL(string: "bucketeer://account/not-a-uuid")!) == nil)
    }

    @Test("Bucket URL missing bucket name is rejected")
    func missingBucket() {
        #expect(BucketeerDeepLink(url: URL(string: "bucketeer://bucket/\(UUID().uuidString)")!) == nil)
    }
}
