//
//  DemoEnvironment.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation
import SwiftUI
import XCTest
import BucketeerCore

/// A fully wired `AppContainer` on in-memory stores, an in-memory
/// Keychain and an in-memory object store, seeded with demo data.
/// Nothing touches the user's container, Keychain or real accounts.
@MainActor
struct DemoEnvironment {
    static let referenceDate = Date(timeIntervalSince1970: 1_793_000_000)

    let container: AppContainer
    let browser: InMemoryS3Browser
    let aws: S3Account
    let azure: S3Account

    var accounts: [S3Account] { [aws, azure] }

    /// `entitlement: nil` derives the state from StoreKit, e.g. an
    /// `SKTestSession` on `Bucketeer.storekit`.
    static func make(entitlement: EntitlementManager.State? = .pro) async throws -> DemoEnvironment {
        let browser = InMemoryS3Browser()
        let container = try AppContainer(configuration: .init(
            stores: .inMemory,
            keychainStore: InMemoryKeychain(),
            s3Browser: browser,
            entitlementState: entitlement,
            startsBackgroundWork: false
        ))
        let aws = S3Account(name: "Demo AWS", provider: .awsS3, region: "eu-central-1")
        let azure = S3Account(name: "Demo Azure", provider: .azureBlob, accountID: "demostorage")
        try await container.accountStore.upsert(aws)
        try await container.accountStore.upsert(azure)
        await seedObjects(in: browser)
        await container.accountListViewModel.refresh()
        return DemoEnvironment(container: container, browser: browser, aws: aws, azure: azure)
    }

    private static func seedObjects(in browser: InMemoryS3Browser) async {
        for bucket in ["photos-2026", "backups", "website-assets"] {
            await browser.addBucket(bucket)
        }
        let files: [(String, Int64)] = [
            ("holiday/beach.jpg", 2_400_000),
            ("holiday/sunset.jpg", 1_900_000),
            ("readme.txt", 1_200),
            ("report.pdf", 840_000),
            ("invoices/2026-10.pdf", 120_000)
        ]
        for (key, size) in files {
            await browser.put(bucket: "photos-2026", key: key, size: size, lastModified: referenceDate)
        }
        await browser.put(bucket: "backups", key: "db/2026-11-01.sql.gz", size: 48_000_000, lastModified: referenceDate)
    }

    /// Browser opened on `photos-2026` with its root listing loaded.
    func openPhotosBucket() async {
        let viewModel = container.browserViewModel
        await viewModel.openAccount(aws)
        await viewModel.openBucket("photos-2026")
    }

    var sampleObject: S3Object {
        S3Object(key: "report.pdf", size: 840_000, lastModified: Self.referenceDate, etag: "etag-report.pdf",
                 contentType: "application/pdf", storageClass: "STANDARD")
    }
}

/// Render + assert helpers shared by the render suites.
@MainActor
extension XCTestCase {
    @discardableResult
    func renderAndAssert<Content: View>(
        _ view: Content,
        name: String,
        size: CGSize = CGSize(width: 900, height: 600),
        shows fragments: [String],
        afterAppear: (@MainActor () async -> Void)? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> OffscreenRenderer.Result {
        let result = try await OffscreenRenderer.render(
            view, name: name, size: size, expected: fragments, afterAppear: afterAppear
        )
        XCTAssertGreaterThan(result.png.count, 1_000, "\(name): empty render", file: file, line: line)
        for fragment in fragments where !result.contains(fragment) {
            XCTFail("\(name): \"\(fragment)\" not rendered. Recognised: \(result.texts)", file: file, line: line)
        }
        return result
    }
}
