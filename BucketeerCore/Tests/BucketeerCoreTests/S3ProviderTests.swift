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

    @Test("Path-style toggle is hidden for AWS and Azure")
    func pathStyleToggleVisibility() {
        #expect(S3Provider.awsS3.supportsPathStyleToggle == false)
        #expect(S3Provider.azureBlob.supportsPathStyleToggle == false)
        for provider in S3Provider.allCases where provider != .awsS3 && provider != .azureBlob {
            #expect(provider.supportsPathStyleToggle == true)
        }
    }

    @Test("Region picker hides only for Azure")
    func regionPickerVisibility() {
        for provider in S3Provider.allCases {
            #expect(provider.hidesRegionPicker == (provider == .azureBlob))
        }
    }

    @Test("Required-accountID providers are Cloudflare R2 and Azure")
    func requiresAccountID() {
        let needs = S3Provider.allCases.filter(\.requiresAccountID)
        #expect(Set(needs) == [.cloudflareR2, .azureBlob])
    }

    @Test("Optional endpoint override only for Azure (sovereign clouds)")
    func optionalEndpointOverride() {
        for provider in S3Provider.allCases {
            #expect(provider.supportsOptionalEndpointOverride == (provider == .azureBlob))
        }
    }

    @Test("Required endpoint override only for Custom")
    func requiredEndpointOverride() {
        for provider in S3Provider.allCases {
            #expect(provider.requiresEndpointOverride == (provider == .custom))
        }
    }

    @Test("Hides access-key field only for Azure (storage account name doubles as key)")
    func hidesAccessKeyField() {
        for provider in S3Provider.allCases {
            #expect(provider.hidesAccessKeyField == (provider == .azureBlob))
        }
    }

    @Test("Default regions are non-empty for every preset except Custom")
    func defaultRegions() {
        for provider in S3Provider.allCases where provider != .custom {
            #expect(!provider.defaultRegion.isEmpty)
        }
        #expect(S3Provider.custom.defaultRegion.isEmpty)
    }

    @Test("Fixed-region list is consistent — defaultRegion is present in fixedRegions when both are defined")
    func defaultRegionAppearsInFixedList() {
        for provider in S3Provider.allCases {
            guard let fixed = provider.fixedRegions else { continue }
            #expect(fixed.contains(provider.defaultRegion))
        }
    }

    @Test("Bucket terminology key is container for Azure, bucket otherwise")
    func bucketTerminology() {
        for provider in S3Provider.allCases {
            let expected = provider == .azureBlob ? "term.container" : "term.bucket"
            #expect(provider.bucketTerminologyKey == expected)
        }
    }
}
