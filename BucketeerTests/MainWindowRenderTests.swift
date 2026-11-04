//
//  MainWindowRenderTests.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import XCTest
import SwiftUI
import BucketeerCore

/// Main window panes, one representative state each.
@MainActor
final class MainWindowRenderTests: XCTestCase {
    private let windowSize = CGSize(width: 1_200, height: 760)

    // MARK: ContentView

    func testContentViewPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.openPhotosBucket()
        try await renderAndAssert(ContentView().environment(demo.container),
                                  name: "ContentView_populated", size: windowSize,
                                  shows: ["report.pdf", "holiday"])
    }

    // MARK: Sidebar

    func testSidebarError() async throws {
        let demo = try await DemoEnvironment.make()
        demo.container.accountListViewModel.error = .persistenceFailure(message: "disk full")
        try await renderAndAssert(sidebar(demo), name: "SidebarView_error", size: sidebarSize, shows: ["disk full"])
    }

    private let sidebarSize = CGSize(width: 280, height: 640)

    private func sidebar(_ demo: DemoEnvironment) -> some View {
        SidebarView(viewModel: demo.container.accountListViewModel, selection: .constant(nil))
            .environment(demo.container)
    }

    // MARK: Bucket list

    func testBucketListPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.container.browserViewModel.openAccount(demo.aws)
        try await renderAndAssert(bucketList(demo), name: "BucketListView_populated",
                                  shows: ["photos-2026", "backups", "website-assets"])
    }

    private func bucketList(_ demo: DemoEnvironment) -> some View {
        BucketListView(viewModel: demo.container.browserViewModel).environment(demo.container)
    }

    // MARK: Object list

    func testObjectListError() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.container.browserViewModel.openAccount(demo.aws)
        await demo.browser.fail(with: .bucketNotFound("photos-2026"))
        await demo.container.browserViewModel.openBucket("photos-2026")
        try await renderAndAssert(objectList(demo), name: "ObjectListView_error",
                                  shows: ["Something Went Wrong", "photos-2026", "was not found"])
    }

    private func objectList(_ demo: DemoEnvironment) -> some View {
        ObjectListView(viewModel: demo.container.browserViewModel).environment(demo.container)
    }

    // MARK: Object detail + breadcrumbs

    /// The preview downloader signs real requests; with no credentials
    /// in the in-memory Keychain it fails before any network access.
    func testObjectDetailError() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.openPhotosBucket()
        demo.container.browserViewModel.selection = ["report.pdf"]
        try await renderAndAssert(objectDetail(demo), name: "ObjectDetailView_error", size: detailSize,
                                  shows: ["Preview failed", "Authentication failed", "840 KB"])
    }

    private let detailSize = CGSize(width: 360, height: 640)

    private func objectDetail(_ demo: DemoEnvironment) -> some View {
        ObjectDetailView(viewModel: demo.container.browserViewModel).environment(demo.container)
    }

    func testBreadcrumbsNested() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.openPhotosBucket()
        demo.container.browserViewModel.prefix = "holiday/2026/"
        try await renderAndAssert(BreadcrumbBar(viewModel: demo.container.browserViewModel),
                                  name: "BreadcrumbBar_nested", size: CGSize(width: 700, height: 44),
                                  shows: ["photos-2026", "holiday", "2026"])
    }

    // MARK: Transfers + menubar

    func testTransferListError() async throws {
        let demo = try await DemoEnvironment.make()
        demo.container.transferQueueViewModel.tasks = demoTransfers(demo)
        try await renderAndAssert(TransferListView(viewModel: demo.container.transferQueueViewModel),
                                  name: "TransferListView_error", shows: ["sunset.jpg", "Network unavailable"])
    }

    func testMenuBarPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        demo.container.transferQueueViewModel.tasks = demoTransfers(demo)
        try await renderAndAssert(MenuBarContent().environment(demo.container),
                                  name: "MenuBarContent_populated", size: menuSize, shows: ["holiday/beach.jpg"])
    }

    private let menuSize = CGSize(width: 340, height: 420)

    private func demoTransfers(_ demo: DemoEnvironment) -> [TransferTask] {
        let folder = FileManager.default.temporaryDirectory
        return [
            TransferTask(direction: .upload, accountID: demo.aws.id, bucket: "photos-2026", key: "holiday/beach.jpg",
                         localURL: folder.appending(path: "beach.jpg"),
                         state: .running(bytesTransferred: 1_200_000, totalBytes: 2_400_000),
                         startedAt: DemoEnvironment.referenceDate),
            TransferTask(direction: .download, accountID: demo.aws.id, bucket: "photos-2026", key: "report.pdf",
                         localURL: folder.appending(path: "report.pdf"), state: .completed,
                         startedAt: DemoEnvironment.referenceDate),
            TransferTask(direction: .upload, accountID: demo.aws.id, bucket: "photos-2026",
                         key: "holiday/sunset.jpg", localURL: folder.appending(path: "sunset.jpg"),
                         state: .failed(message: "Network unavailable."),
                         startedAt: DemoEnvironment.referenceDate)
        ]
    }
}
