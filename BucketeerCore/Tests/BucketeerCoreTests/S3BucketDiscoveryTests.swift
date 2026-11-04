//
//  S3BucketDiscoveryTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import Security
import Testing
@preconcurrency import SotoS3
@testable import BucketeerCore

/// Which buckets an account shows and how a failed sign-in is
/// explained. Stubbed list/probe calls; no network, no Keychain.
@Suite("S3BucketDiscovery")
struct S3BucketDiscoveryTests {

    private struct Unexpected: Error {}

    private func account(_ provider: S3Provider = .civo, region: String = "lon1", bucket: String? = nil) -> S3Account {
        S3Account(name: "Test", provider: provider, region: region, defaultBucket: bucket)
    }

    @Test("A named bucket is checked directly and is the only bucket shown")
    func namedBucketReplacesListing() async throws {
        let probed = ProbeLog()

        let buckets = try await S3BucketDiscovery.buckets(
            for: account(bucket: " photos "),
            listAll: { throw Unexpected() },
            probe: { await probed.record($0) }
        )

        #expect(buckets.map(\.name) == ["photos"])
        #expect(await probed.names == ["photos"])
    }

    @Test("A key that may not list buckets asks for the bucket name")
    func listingDeniedAsksForBucketName() async {
        await #expect(throws: BucketeerError.bucketListingDenied) {
            try await S3BucketDiscovery.buckets(
                for: account(),
                listAll: { throw S3ErrorType.accessDenied },
                probe: { _ in }
            )
        }
    }

    @Test("An access key unknown in the region names the provider and the region")
    func unknownAccessKeyNamesTheRegion() async {
        let error = await failure {
            try await S3BucketDiscovery.buckets(
                for: account(),
                listAll: { throw AWSResponseError(errorCode: "InvalidAccessKeyId") },
                probe: { _ in }
            )
        }

        #expect(error == .accessKeyNotRecognized(provider: .civo, region: "lon1"))
        #expect(error?.errorDescription?.contains("lon1") == true)
    }

    @Test("A wrong secret key is reported as such")
    func wrongSecretKeyIsNamed() async {
        let error = await failure {
            try await S3BucketDiscovery.buckets(
                for: account(bucket: "photos"),
                listAll: { [] },
                probe: { _ in throw AWSResponseError(errorCode: "SignatureDoesNotMatch") }
            )
        }

        #expect(error == .secretKeyMismatch)
    }

    @Test("A named bucket that does not exist is reported by name")
    func missingNamedBucketIsNamed() async {
        let error = await failure {
            try await S3BucketDiscovery.buckets(
                for: account(bucket: "photos"),
                listAll: { [] },
                probe: { _ in throw S3ErrorType.noSuchBucket }
            )
        }

        #expect(error == .bucketNotFound("photos"))
    }

    @Test("A Keychain item that is not there means missing credentials, not a failed sign-in")
    func missingKeychainItemMeansMissingCredentials() {
        #expect(KeychainStore.loadError(for: errSecItemNotFound) == .credentialsMissing)
        #expect(KeychainStore.loadError(for: errSecInteractionNotAllowed)
                == .keychainFailure(status: errSecInteractionNotAllowed))
    }

    private func failure(_ body: () async throws -> [S3Bucket]) async -> BucketeerError? {
        do {
            _ = try await body()
            return nil
        } catch {
            return error as? BucketeerError
        }
    }
}

private actor ProbeLog {
    private(set) var names: [String] = []
    func record(_ name: String) { names.append(name) }
}
