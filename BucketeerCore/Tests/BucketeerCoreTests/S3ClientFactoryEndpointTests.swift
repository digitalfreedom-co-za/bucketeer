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

    struct TemplateCase: Sendable, CustomTestStringConvertible {
        let provider: S3Provider
        let region: String
        var accountID: String?
        let expected: String

        var testDescription: String { "\(provider) → \(expected)" }
    }

    @Test("Each provider resolves to its endpoint template", arguments: [
        TemplateCase(provider: .awsS3, region: "eu-central-1", expected: "https://s3.eu-central-1.amazonaws.com"),
        // The China partition has its own DNS suffix.
        TemplateCase(provider: .awsS3, region: "cn-north-1", expected: "https://s3.cn-north-1.amazonaws.com.cn"),
        TemplateCase(provider: .awsS3, region: "cn-northwest-1", expected: "https://s3.cn-northwest-1.amazonaws.com.cn"),
        TemplateCase(provider: .civo, region: "fra1", expected: "https://objectstore.fra1.civo.com"),
        TemplateCase(provider: .cloudflareR2, region: "auto", accountID: "abc123",
                     expected: "https://abc123.r2.cloudflarestorage.com"),
        TemplateCase(provider: .cloudflareR2, region: "auto",
                     expected: "https://missing-account-id.r2.cloudflarestorage.com"),
        TemplateCase(provider: .backblazeB2, region: "us-west-002", expected: "https://s3.us-west-002.backblazeb2.com"),
        TemplateCase(provider: .wasabi, region: "eu-central-1", expected: "https://s3.eu-central-1.wasabisys.com"),
        TemplateCase(provider: .digitalOceanSpaces, region: "fra1", expected: "https://fra1.digitaloceanspaces.com"),
        TemplateCase(provider: .storj, region: "global", expected: "https://gateway.storjshare.io"),
        TemplateCase(provider: .azureBlob, region: "auto", accountID: "myaccount",
                     expected: "https://myaccount.blob.core.windows.net"),
        TemplateCase(provider: .custom, region: "", expected: "https://localhost")
    ])
    func providerTemplate(_ testCase: TemplateCase) {
        let url = S3ClientFactory.endpoint(
            for: account(provider: testCase.provider, region: testCase.region, accountID: testCase.accountID)
        )
        #expect(url.absoluteString == testCase.expected)
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
}

@Suite("Presigned URL path")
struct PresignedURLPathTests {
    @Test("Object keys are percent-encoded exactly once")
    func keyEncodedOnce() {
        let url = S3Service.presignTargetURL(
            endpoint: URL(string: "https://s3.example.com")!,
            bucket: "bkt",
            key: "my folder/a?b#c%e.txt",
            virtualHost: false
        )
        #expect(url.absoluteString == "https://s3.example.com/bkt/my%20folder/a%3Fb%23c%25e.txt")
    }

    @Test("A virtual-host account gets the bucket in the host, as its requests do")
    func virtualHostURL() {
        let url = S3Service.presignTargetURL(
            endpoint: URL(string: "https://fra1.digitaloceanspaces.com")!,
            bucket: "bkt",
            key: "a b.txt",
            virtualHost: true
        )
        #expect(url.absoluteString == "https://bkt.fra1.digitaloceanspaces.com/a%20b.txt")
    }

    @Test("Presigned URLs for AWS China use the China endpoint")
    func chinaPresignURL() {
        let account = S3Account(id: UUID(), name: "T", provider: .awsS3, region: "cn-northwest-1")
        let url = S3Service.presignTargetURL(
            endpoint: S3ClientFactory.endpoint(for: account),
            bucket: "bkt",
            key: "a.txt",
            virtualHost: S3Service.usesVirtualHost(account: account, bucket: "bkt")
        )
        #expect(url.absoluteString == "https://bkt.s3.cn-northwest-1.amazonaws.com.cn/a.txt")
    }

    @Test("Addressing follows the request rules: dotted buckets stay path-style")
    func addressingRule() {
        let spaces = S3Account(id: UUID(), name: "T", provider: .digitalOceanSpaces, region: "fra1")
        #expect(S3Service.usesVirtualHost(account: spaces, bucket: "bkt"))
        #expect(!S3Service.usesVirtualHost(account: spaces, bucket: "my.bkt"))
        let civo = S3Account(id: UUID(), name: "T", provider: .civo, region: "fra1")
        #expect(!S3Service.usesVirtualHost(account: civo, bucket: "bkt"))
    }
}
