//
//  SheetRenderTests.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import XCTest
import SwiftUI
import StoreKitTest
import BucketeerCore

/// Sheets of the browser, account and paywall flows, one state each.
@MainActor
final class SheetRenderTests: XCTestCase {
    private let sheetSize = CGSize(width: 560, height: 640)
    private let wideSheetSize = CGSize(width: 760, height: 640)

    func testNewFolderSheet() async throws {
        try await renderAndAssert(NewFolderSheet(onCreate: { _ in }),
                                  name: "NewFolderSheet_empty", size: CGSize(width: 420, height: 220), shows: ["New folder"])
    }

    /// Renaming starts from the current name.
    func testRenameSheetPrefilled() async throws {
        try await renderAndAssert(RenameSheet(original: "report.pdf", onRename: { _ in }),
                                  name: "RenameSheet_populated", size: CGSize(width: 420, height: 220),
                                  shows: ["report.pdf"])
    }

    // MARK: Cross-account copy

    func testCrossAccountCopyPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(
            CrossAccountCopySheet(sourceAccount: demo.aws, sourceBucket: "photos-2026",
                                  keys: ["report.pdf", "readme.txt"], accounts: demo.accounts,
                                  isEncryptedToPlain: { _, _ in false },
                                  onSubmit: { _, _, _, _, _ in [] }),
            name: "CrossAccountCopySheet_populated", size: sheetSize,
            shows: ["photos-2026", "Keep source objects"])
    }

    // MARK: Accounts

    /// Editing loads the stored account into the form.
    func testEditAccountPrefilled() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(AddEditAccountSheet(mode: .edit(demo.aws), onSave: { _, _ in nil }),
                                  name: "AddEditAccountSheet_populated", size: CGSize(width: 560, height: 720),
                                  shows: ["Demo AWS"])
    }

    /// A key scoped to one bucket needs its name; the field sits with
    /// the connection settings, not behind Advanced.
    func testEditAccountShowsBucketField() async throws {
        let account = S3Account(name: "Civo Photos", provider: .civo, region: "fra1", defaultBucket: "team-photos")
        try await renderAndAssert(AddEditAccountSheet(mode: .edit(account), onSave: { _, _ in nil }),
                                  name: "AddEditAccountSheet_bucket", size: CGSize(width: 560, height: 720),
                                  shows: ["Bucket (optional)", "team-photos"])
    }

    // MARK: Share link

    func testPresignedURLPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(presign(demo), name: "PresignedURLSheet_populated", size: sheetSize,
                                  shows: ["report.pdf", "Link ready", "demo.invalid"])
    }

    private func presign(_ demo: DemoEnvironment) -> some View {
        PresignedURLSheet(account: demo.aws, bucket: "photos-2026", object: demo.sampleObject,
                          generator: demo.browser, activityLog: nil)
    }

    // MARK: Bucket dashboard

    func testBucketDashboardPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(dashboard(demo, bucket: "photos-2026"),
                                  name: "BucketDashboardSheet_populated", size: dashboardSize,
                                  shows: ["photos-2026", "Largest objects", "holiday/beach.jpg"])
    }

    private let dashboardSize = CGSize(width: 720, height: 700)

    private func dashboard(_ demo: DemoEnvironment, bucket: String) -> some View {
        BucketDashboardSheet(viewModel: BucketDashboardViewModel(account: demo.aws, bucket: bucket, browser: demo.browser))
    }

    // MARK: Metadata + versions

    func testObjectMetadataPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(metadata(demo), name: "ObjectMetadataSheet_populated", size: wideSheetSize,
                                  shows: ["text/plain", "owner", "STANDARD"])
    }

    private func metadata(_ demo: DemoEnvironment) -> some View {
        ObjectMetadataSheet(viewModel: ObjectMetadataViewModel(account: demo.aws, bucket: "photos-2026",
                                                               key: "report.pdf", browser: demo.browser))
    }

    func testObjectVersionsPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(versions(demo, key: "report.pdf"), name: "ObjectVersionsSheet_populated",
                                  size: wideSheetSize, shows: ["v2", "v1", "840 KB"])
    }

    private func versions(_ demo: DemoEnvironment, key: String) -> some View {
        ObjectVersionsSheet(viewModel: ObjectVersionsViewModel(account: demo.aws, bucket: "photos-2026",
                                                               key: key, browser: demo.browser))
    }

    // MARK: Paywall

    func testPaywallFree() async throws {
        let demo = try await DemoEnvironment.make(entitlement: .free)
        try await renderAndAssert(PaywallSheet(feature: .syncEngine).environment(demo.container),
                                  name: "PaywallSheet_free", size: sheetSize, shows: ["Sync jobs need Pro"])
    }

    /// The paywall as App Review sees it: products from the local
    /// StoreKit configuration (German storefront), trial not yet claimed.
    /// The PNG doubles as the in-app purchase review screenshot.
    ///
    /// storekitagent refuses a test session for the `xctest` tool itself
    /// (no Launch Services record for its bundle id), so this bundle
    /// unhosted under `xcodebuild test` can never load products. It runs
    /// in a runner process with its own bundle id instead.
    func testPaywallWithStoreKitProducts() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.processName == "xctest",
                      "StoreKit test sessions need a process with its own bundle id")
        let configuration = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Bucketeer", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: configuration)
        session.disableDialogs = true
        session.storefront = "DEU"
        session.locale = Locale(identifier: "en_US")
        session.clearTransactions()
        let demo = try await DemoEnvironment.make(entitlement: nil)
        let entitlement = demo.container.entitlementManager
        await entitlement.bootstrap()
        XCTAssertEqual(entitlement.product?.displayPrice, "€14.99")
        XCTAssertNotNil(entitlement.trialProduct)
        XCTAssertTrue(entitlement.isTrialAvailable)
        // Drawn like the key window it is in the app; the off-screen
        // window never becomes key and would grey out the buy button.
        try await renderAndAssert(PaywallSheet(feature: nil).environment(demo.container)
                                    .environment(\.controlActiveState, .key),
                                  name: "PaywallSheet_storeKit", size: CGSize(width: 480, height: 780),
                                  shows: ["Pro Lifetime — €14.99", "14-day Trial", "Start trial",
                                          "Restore purchase", "Redeem Code"])
        session.clearTransactions()
    }
}
