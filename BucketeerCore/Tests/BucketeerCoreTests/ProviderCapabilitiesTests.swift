//
//  ProviderCapabilitiesTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// What each provider enforces decides whether a condition travels as a
/// header or is checked by the app right before the request. A header
/// the provider ignores (or refuses although it holds) must never be
/// relied on. Sources: high14/PROVIDERS.md.
@Suite("Provider capabilities")
struct ProviderCapabilitiesTests {

    struct Expectation: Sendable, CustomTestStringConvertible {
        let provider: S3Provider
        let conditions: S3Provider.ConditionalRequests
        var testDescription: String { "\(provider)" }
    }

    @Test("Only documented (or live-tested) conditions are enforced", arguments: [
        // AWS: conditional writes incl. completion and copy, conditional deletes.
        Expectation(provider: .awsS3, conditions: .all),
        // R2: PutObject conditions and copy-source conditions; none on completion or delete.
        Expectation(provider: .cloudflareR2, conditions: [.writeIfMatch, .writeIfAbsent, .copySourceIfMatch]),
        // Spaces: copy-source conditions only.
        Expectation(provider: .digitalOceanSpaces, conditions: [.copySourceIfMatch]),
        // Not documented.
        Expectation(provider: .backblazeB2, conditions: []),
        Expectation(provider: .wasabi, conditions: []),
        Expectation(provider: .storj, conditions: []),
        // Live test: If-Match always 412, the rest ignored.
        Expectation(provider: .civo, conditions: []),
        // Unknown server: conservative.
        Expectation(provider: .custom, conditions: []),
        Expectation(provider: .azureBlob, conditions: .all)
    ])
    func conditionMatrix(_ expectation: Expectation) {
        #expect(expectation.provider.conditionalRequests == expectation.conditions)
    }

    @Test("R2 always signs for region auto, whatever was stored")
    func r2SignsForAuto() {
        #expect(S3Provider.cloudflareR2.signingRegion(for: "weur") == "auto")
        #expect(S3Provider.cloudflareR2.fixedRegions == ["auto"])
        #expect(S3Provider.civo.signingRegion(for: "fra1") == "fra1")
    }

    @Test("Region lists follow the providers' documentation")
    func documentedRegions() throws {
        let civo = try #require(S3Provider.civo.fixedRegions)
        #expect(Set(civo) == ["fra1", "lon1", "nyc1", "mum1"])
        let spaces = try #require(S3Provider.digitalOceanSpaces.fixedRegions)
        #expect(Set(spaces) == ["nyc3", "ams3", "sfo2", "sfo3", "sgp1", "lon1", "fra1", "tor1",
                                "blr1", "syd1", "atl1", "ric1", "mkc1"])
        let wasabi = try #require(S3Provider.wasabi.fixedRegions)
        #expect(Set(wasabi) == ["us-east-1", "us-east-2", "us-central-1", "us-west-1", "us-west-2",
                                "ca-central-1", "eu-central-1", "eu-central-2", "eu-west-1", "eu-west-2",
                                "eu-west-3", "eu-south-1", "ap-northeast-1", "ap-northeast-2",
                                "ap-southeast-1", "ap-southeast-2"])
        let aws = try #require(S3Provider.awsS3.fixedRegions)
        #expect(Set(["ap-east-2", "ap-southeast-6", "mx-central-1"]).isSubset(of: Set(aws)))
        let b2 = try #require(S3Provider.backblazeB2.fixedRegions)
        #expect(b2.contains("us-east-005"))
    }

    @Test("A condition that holds lets the request go ahead")
    func holdingConditionsPass() throws {
        try PreconditionCheck.verify(.ifMatch("abc"), current: "\"abc\"", key: "k")
        try PreconditionCheck.verify(.ifAbsent, current: nil, key: "k")
    }

    @Test("A changed, missing or existing object fails the check")
    func failingConditionsThrow() {
        #expect(throws: BucketeerError.preconditionFailed(key: "k")) {
            try PreconditionCheck.verify(.ifMatch("abc"), current: "def", key: "k")
        }
        #expect(throws: BucketeerError.preconditionFailed(key: "k")) {
            try PreconditionCheck.verify(.ifMatch("abc"), current: nil, key: "k")
        }
        #expect(throws: BucketeerError.preconditionFailed(key: "k")) {
            try PreconditionCheck.verify(.ifAbsent, current: "abc", key: "k")
        }
    }
}
