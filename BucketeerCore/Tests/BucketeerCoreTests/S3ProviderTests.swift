//
//  S3ProviderTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// Locks down the per-provider defaults that the rest of the app (and
/// the user's onboarding flow) treats as ground truth. Drift here would
/// silently change addressing-style behaviour or break endpoint
/// resolution for accounts the user adds after the change.
@Suite("S3Provider defaults")
struct S3ProviderTests {

    @Test("Family routing — only Azure uses .azureBlob family")
    func familyRouting() {
        for provider in S3Provider.allCases {
            switch provider {
            case .azureBlob:
                #expect(provider.family == .azureBlob)
            default:
                #expect(provider.family == .s3)
            }
        }
    }

    @Test("Path-style defaults match the design table")
    func pathStyleDefaults() {
        #expect(S3Provider.awsS3.usesPathStyleByDefault == false)
        #expect(S3Provider.civo.usesPathStyleByDefault == true)
        #expect(S3Provider.cloudflareR2.usesPathStyleByDefault == false)
        #expect(S3Provider.backblazeB2.usesPathStyleByDefault == false)
        #expect(S3Provider.wasabi.usesPathStyleByDefault == false)
        #expect(S3Provider.digitalOceanSpaces.usesPathStyleByDefault == false)
        #expect(S3Provider.storj.usesPathStyleByDefault == true)
        #expect(S3Provider.azureBlob.usesPathStyleByDefault == false)
        #expect(S3Provider.custom.usesPathStyleByDefault == true)
    }
}
