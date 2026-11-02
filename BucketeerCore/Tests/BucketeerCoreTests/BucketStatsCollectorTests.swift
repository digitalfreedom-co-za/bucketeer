//
//  BucketStatsCollectorTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import Testing
@testable import BucketeerCore

@Suite("BucketStatsCollector")
struct BucketStatsCollectorTests {

    @Test("insertLargest keeps a descending top-N buffer under capacity")
    func underCapacity() {
        var buf: [(key: String, size: Int64)] = []
        BucketStatsCollector.insertLargest(&buf, key: "a", size: 5, keep: 3)
        BucketStatsCollector.insertLargest(&buf, key: "b", size: 10, keep: 3)
        BucketStatsCollector.insertLargest(&buf, key: "c", size: 1, keep: 3)
        #expect(buf.map(\.size) == [10, 5, 1])
    }

    @Test("insertLargest evicts the smallest when at capacity")
    func atCapacityEvicts() {
        var buf: [(key: String, size: Int64)] = []
        for (k, s) in [("a", 1), ("b", 2), ("c", 3)] {
            BucketStatsCollector.insertLargest(&buf, key: k, size: Int64(s), keep: 3)
        }
        BucketStatsCollector.insertLargest(&buf, key: "d", size: 4, keep: 3)
        #expect(buf.map(\.size) == [4, 3, 2])
        #expect(!buf.contains(where: { $0.key == "a" }))
    }

    @Test("insertLargest ignores items smaller than the current minimum")
    func ignoresSmaller() {
        var buf: [(key: String, size: Int64)] = []
        for (k, s) in [("a", 10), ("b", 20), ("c", 30)] {
            BucketStatsCollector.insertLargest(&buf, key: k, size: Int64(s), keep: 3)
        }
        BucketStatsCollector.insertLargest(&buf, key: "tiny", size: 1, keep: 3)
        #expect(buf.map(\.size) == [30, 20, 10])
    }
}

@Suite("BucketStatsCollector walk")
struct BucketStatsCollectorWalkTests {
    @Test("Objects in nested folders are counted, across pages")
    func countsNestedObjects() async throws {
        let browser = InMemoryS3Browser(pageSize: 2)
        await browser.addBucket("b")
        await browser.put(bucket: "b", key: "root.txt", size: 1)
        await browser.put(bucket: "b", key: "a/one.txt", size: 10)
        await browser.put(bucket: "b", key: "a/two.txt", size: 20)
        await browser.put(bucket: "b", key: "a/deep/three.txt", size: 300)
        let collector = BucketStatsCollector(browser: browser)

        let stats = try await collector.collect(account: S3Account(name: "Demo", provider: .awsS3), bucket: "b")

        #expect(stats.objectCount == 4)
        #expect(stats.folderCount == 2)
        #expect(stats.totalBytes == 331)
        #expect(stats.largestObjects.first?.key == "a/deep/three.txt")
    }
}

@Suite("ProviderPricing")
struct ProviderPricingTests {

    @Test("Estimate is non-nil for every concrete provider except .custom")
    func everyProviderHasRate() {
        for provider in S3Provider.allCases {
            let usd = ProviderPricing.estimateMonthlyUSD(bytes: 1_073_741_824, provider: provider)
            if provider == .custom {
                #expect(usd == nil)
            } else {
                #expect(usd != nil)
                #expect((usd ?? 0) >= 0)
            }
        }
    }

    @Test("1 GB on AWS is the rate per GB-month")
    func awsRate() {
        let usd = ProviderPricing.estimateMonthlyUSD(bytes: 1_073_741_824, provider: .awsS3) ?? 0
        #expect(abs(usd - 0.023) < 0.0001)
    }
}
