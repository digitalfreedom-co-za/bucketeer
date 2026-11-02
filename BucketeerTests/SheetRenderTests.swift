//
//  SheetRenderTests.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import XCTest
import SwiftUI
import BucketeerCore

/// Sheets of the browser and account flows. Sheets without an error
/// presentation of their own (they report failures to the presenting
/// view) are rendered in the states they have.
@MainActor
final class SheetRenderTests: XCTestCase {
    private let sheetSize = CGSize(width: 560, height: 640)
    private let wideSheetSize = CGSize(width: 760, height: 640)

    func testNewFolderSheetEmpty() async throws {
        try await renderAndAssert(NewFolderSheet(onCreate: { _ in }),
                                  name: "NewFolderSheet_empty", size: CGSize(width: 420, height: 220), shows: ["New folder"])
    }

    func testRenameSheetPopulated() async throws {
        try await renderAndAssert(RenameSheet(original: "report.pdf", onRename: { _ in }),
                                  name: "RenameSheet_populated", size: CGSize(width: 420, height: 220),
                                  shows: ["report.pdf"])
    }

    // MARK: Share link

    func testPresignedURLPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(presign(demo), name: "PresignedURLSheet_populated", size: sheetSize,
                                  shows: ["report.pdf", "Link ready", "demo.invalid"])
    }

    func testPresignedURLError() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.browser.fail(with: .authenticationFailed)
        try await renderAndAssert(presign(demo), name: "PresignedURLSheet_error", size: sheetSize,
                                  shows: ["Authentication failed"])
    }

    private func presign(_ demo: DemoEnvironment) -> some View {
        PresignedURLSheet(account: demo.aws, bucket: "photos-2026", object: demo.sampleObject,
                          generator: demo.browser, activityLog: nil)
    }

    // MARK: Cross-account copy

    func testCrossAccountCopyEmpty() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(
            CrossAccountCopySheet(sourceAccount: demo.aws, sourceBucket: "photos-2026", keys: ["report.pdf"],
                                  accounts: [demo.aws], onSubmit: { _, _, _, _ in [] }),
            name: "CrossAccountCopySheet_empty", size: sheetSize, shows: ["None selected"])
    }

    func testCrossAccountCopyPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(
            CrossAccountCopySheet(sourceAccount: demo.aws, sourceBucket: "photos-2026",
                                  keys: ["report.pdf", "readme.txt"], accounts: demo.accounts,
                                  onSubmit: { _, _, _, _ in [] }),
            name: "CrossAccountCopySheet_populated", size: sheetSize,
                                  shows: ["photos-2026", "Keep source objects"])
    }

    // MARK: Bucket dashboard

    func testBucketDashboardEmpty() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(dashboard(demo, bucket: "website-assets"),
                                  name: "BucketDashboardSheet_empty", size: dashboardSize, shows: ["website-assets"])
    }

    func testBucketDashboardPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(dashboard(demo, bucket: "photos-2026"),
                                  name: "BucketDashboardSheet_populated", size: dashboardSize,
                                  shows: ["photos-2026", "Largest objects", "holiday/beach.jpg"])
    }

    func testBucketDashboardError() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.browser.fail(with: .networkUnavailable)
        try await renderAndAssert(dashboard(demo, bucket: "photos-2026"),
                                  name: "BucketDashboardSheet_error", size: dashboardSize, shows: ["Network unavailable"])
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

    func testObjectMetadataError() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.browser.fail(with: .objectNotFound(key: "report.pdf"))
        try await renderAndAssert(metadata(demo), name: "ObjectMetadataSheet_error", size: wideSheetSize,
                                  shows: ["was not found"])
    }

    private func metadata(_ demo: DemoEnvironment) -> some View {
        ObjectMetadataSheet(viewModel: ObjectMetadataViewModel(account: demo.aws, bucket: "photos-2026",
                                                               key: "report.pdf", browser: demo.browser))
    }

    func testObjectVersionsEmpty() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(versions(demo, key: "missing.txt"), name: "ObjectVersionsSheet_empty",
                                  size: wideSheetSize, shows: ["No versions recorded"])
    }

    func testObjectVersionsPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(versions(demo, key: "report.pdf"), name: "ObjectVersionsSheet_populated",
                                  size: wideSheetSize, shows: ["v2", "v1", "840 KB"])
    }

    func testObjectVersionsError() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.browser.fail(with: .featureNotSupported(featureKey: "versioning"))
        try await renderAndAssert(versions(demo, key: "report.pdf"), name: "ObjectVersionsSheet_error",
                                  size: wideSheetSize, shows: ["does not support"])
    }

    private func versions(_ demo: DemoEnvironment, key: String) -> some View {
        ObjectVersionsSheet(viewModel: ObjectVersionsViewModel(account: demo.aws, bucket: "photos-2026",
                                                               key: key, browser: demo.browser))
    }

    // MARK: Accounts

    func testAddAccountEmpty() async throws {
        try await renderAndAssert(AddEditAccountSheet(mode: .create, onSave: { _, _ in nil }),
                                  name: "AddEditAccountSheet_empty", size: accountSize, shows: ["Access Key ID"])
    }

    func testEditAccountPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(AddEditAccountSheet(mode: .edit(demo.aws), onSave: { _, _ in nil }),
                                  name: "AddEditAccountSheet_populated", size: accountSize, shows: ["Demo AWS"])
    }

    private let accountSize = CGSize(width: 560, height: 720)

    // MARK: Paywall

    func testPaywallTrial() async throws {
        let demo = try await DemoEnvironment.make(entitlement: .trial(daysRemaining: 9))
        try await renderAndAssert(PaywallSheet(feature: .mountDrive).environment(demo.container),
                                  name: "PaywallSheet_trial", size: sheetSize, shows: ["Bucketeer Pro", "Restore purchase"])
    }

    func testPaywallFree() async throws {
        let demo = try await DemoEnvironment.make(entitlement: .free)
        try await renderAndAssert(PaywallSheet(feature: .syncEngine).environment(demo.container),
                                  name: "PaywallSheet_free", size: sheetSize, shows: ["Sync jobs need Pro"])
    }

    func testPaywallPro() async throws {
        let demo = try await DemoEnvironment.make(entitlement: .pro)
        try await renderAndAssert(PaywallSheet(feature: nil).environment(demo.container),
                                  name: "PaywallSheet_pro", size: sheetSize, shows: ["Bucketeer Pro"])
    }
}
