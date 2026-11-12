//
//  EncryptionKeyCreationTests.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 12.11.26.
//

import XCTest
import FileProvider
import BucketeerCore

/// Rules: a manually entered bucket must exist and be readable before a
/// key is created, and a stored key whose list or File Provider mirror
/// could not be refreshed is reported, then finished without a second
/// key. Runs on in-memory stores and a temporary mirror file.
@MainActor
final class EncryptionKeyCreationTests: XCTestCase {
    private let account = S3Account(name: "Demo", provider: .awsS3)

    func testManualBucketMustExistAndBeReachable() async throws {
        let browser = InMemoryS3Browser()
        await browser.addBucket("photos")
        let viewModel = makeViewModel(browser: browser)

        try await viewModel.verifyBucket("photos", account: account)
        do {
            try await viewModel.verifyBucket("phootos", account: account)
            XCTFail("A valid-looking but missing bucket must be refused")
        } catch let error as BucketVerificationError {
            XCTAssertEqual(error, .notFound)
        }

        await browser.fail(with: .networkUnavailable)
        do {
            try await viewModel.verifyBucket("photos", account: account)
            XCTFail("An unreachable bucket must not count as verified")
        } catch let error as BucketVerificationError {
            let reason = try XCTUnwrap(BucketeerError.networkUnavailable.errorDescription)
            XCTAssertEqual(error, .unverifiable(reason: reason))
        }
    }

    func testRefreshFailureAfterCreationIsReportedAndRetriedWithoutSecondKey() async throws {
        let store = InMemoryEncryptionKeyStore()
        let mirrorDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: mirrorDirectory) }
        let mirrorURL = mirrorDirectory.appending(path: "encrypted-buckets.json")
        let viewModel = makeViewModel(keyStore: store, mirrorURL: mirrorURL)

        do {
            try await viewModel.create(label: "Photos", account: account, bucket: "photos")
            XCTFail("A failed mirror write must not report success")
        } catch is EncryptionKeyRefreshError {}
        let stored = await store.all()
        XCTAssertEqual(stored.count, 1)
        XCTAssertNotNil(viewModel.error)

        try FileManager.default.createDirectory(at: mirrorDirectory, withIntermediateDirectories: true)
        try await viewModel.finishCreation(account: account, bucket: "photos")
        let afterRetry = await store.all()
        let entry = EncryptedBucketList.entry(accountID: account.id, bucket: "photos")
        XCTAssertEqual(afterRetry, stored)
        XCTAssertTrue(try EncryptedBucketList.contains(domainIdentifier: entry, at: mirrorURL))
        XCTAssertNil(viewModel.error)
    }

    private func makeViewModel(
        keyStore: InMemoryEncryptionKeyStore = InMemoryEncryptionKeyStore(),
        browser: InMemoryS3Browser = InMemoryS3Browser(),
        mirrorURL: URL? = nil
    ) -> EncryptionKeysViewModel {
        EncryptionKeysViewModel(
            keyStore: keyStore,
            accountStore: SingleAccountStore(account: account),
            s3Browser: browser,
            gate: BucketEncryptionGate(keyStore: keyStore),
            mountController: MountController(encryptionKeyStore: keyStore, registry: NoMountedDomains()),
            encryptedBucketListURL: mirrorURL
        )
    }
}

private struct SingleAccountStore: AccountStoring {
    let account: S3Account

    func all() -> [S3Account] { [account] }
    func upsert(_ account: S3Account) {}
    func delete(id: UUID) {}
    func touchLastUsed(id: UUID) {}
}

private struct NoMountedDomains: FileProviderDomainRegistry {
    func identifiers() -> [NSFileProviderDomainIdentifier] { [] }
    func add(identifier: NSFileProviderDomainIdentifier, displayName: String) {}
    func remove(identifier: NSFileProviderDomainIdentifier) {}
    func signalWorkingSet(identifier: NSFileProviderDomainIdentifier) {}
}
