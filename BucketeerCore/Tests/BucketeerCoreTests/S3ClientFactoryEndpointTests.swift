//
//  S3ClientFactoryEndpointTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// Locks the per-provider endpoint URL template down. Changing one of
/// these values would silently route a user's bucket traffic to a
/// different host on the next launch.
@Suite("S3ClientFactory.endpoint(for:)")
struct S3ClientFactoryEndpointTests {

    private func account(
        provider: S3Provider,
        region: String,
        accountID: String? = nil,
        endpointOverride: URL? = nil
    ) -> S3Account {
        S3Account(
            id: UUID(),
            name: "Test",
            provider: provider,
            region: region,
            endpointOverride: endpointOverride,
            accountID: accountID
        )
    }

    @Test("AWS endpoint uses standard regional host")
    func awsEndpoint() {
        let url = S3ClientFactory.endpoint(for: account(provider: .awsS3, region: "eu-central-1"))
        #expect(url.absoluteString == "https://s3.eu-central-1.amazonaws.com")
    }

    @Test("Civo endpoint uses objectstore.<region>.civo.com")
    func civoEndpoint() {
        let url = S3ClientFactory.endpoint(for: account(provider: .civo, region: "fra1"))
        #expect(url.absoluteString == "https://objectstore.fra1.civo.com")
    }

    @Test("Cloudflare R2 endpoint embeds the account ID")
    func cloudflareR2Endpoint() {
        let url = S3ClientFactory.endpoint(
            for: account(provider: .cloudflareR2, region: "auto", accountID: "abc123")
        )
        #expect(url.absoluteString == "https://abc123.r2.cloudflarestorage.com")
    }

    @Test("Cloudflare R2 falls back to placeholder when account ID is missing")
    func cloudflareR2NoAccountID() {
        let url = S3ClientFactory.endpoint(
            for: account(provider: .cloudflareR2, region: "auto")
        )
        #expect(url.absoluteString == "https://missing-account-id.r2.cloudflarestorage.com")
    }

    @Test("Backblaze B2 endpoint uses backblazeb2.com domain")
    func backblazeB2Endpoint() {
        let url = S3ClientFactory.endpoint(for: account(provider: .backblazeB2, region: "us-west-002"))
        #expect(url.absoluteString == "https://s3.us-west-002.backblazeb2.com")
    }

    @Test("Wasabi endpoint uses wasabisys.com domain")
    func wasabiEndpoint() {
        let url = S3ClientFactory.endpoint(for: account(provider: .wasabi, region: "eu-central-1"))
        #expect(url.absoluteString == "https://s3.eu-central-1.wasabisys.com")
    }

    @Test("DigitalOcean Spaces uses <region>.digitaloceanspaces.com")
    func digitalOceanEndpoint() {
        let url = S3ClientFactory.endpoint(
            for: account(provider: .digitalOceanSpaces, region: "fra1")
        )
        #expect(url.absoluteString == "https://fra1.digitaloceanspaces.com")
    }

    @Test("Storj uses the fixed gateway host (region-independent)")
    func storjEndpoint() {
        let url = S3ClientFactory.endpoint(for: account(provider: .storj, region: "global"))
        #expect(url.absoluteString == "https://gateway.storjshare.io")
    }

    @Test("Azure endpoint defaults to <accountID>.blob.core.windows.net")
    func azureEndpoint() {
        let url = S3ClientFactory.endpoint(
            for: account(provider: .azureBlob, region: "auto", accountID: "myaccount")
        )
        #expect(url.absoluteString == "https://myaccount.blob.core.windows.net")
    }

    @Test("Azure endpoint respects sovereign-cloud override")
    func azureSovereignOverride() {
        let override = URL(string: "https://myaccount.blob.core.chinacloudapi.cn")!
        let url = S3ClientFactory.endpoint(
            for: account(
                provider: .azureBlob,
                region: "auto",
                accountID: "myaccount",
                endpointOverride: override
            )
        )
        #expect(url == override)
    }

    @Test("Custom endpoint uses the override directly")
    func customEndpoint() {
        let override = URL(string: "https://minio.local:9000")!
        let url = S3ClientFactory.endpoint(
            for: account(provider: .custom, region: "", endpointOverride: override)
        )
        #expect(url == override)
    }

    @Test("Custom falls back to localhost when no override is set")
    func customNoOverride() {
        let url = S3ClientFactory.endpoint(for: account(provider: .custom, region: ""))
        #expect(url.absoluteString == "https://localhost")
    }
}
