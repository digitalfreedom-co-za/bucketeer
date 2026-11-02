//
//  MainWindowRenderTests.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import XCTest
import SwiftUI
import BucketeerCore

/// Main window panes in empty, populated and error states.
@MainActor
final class MainWindowRenderTests: XCTestCase {
    private let windowSize = CGSize(width: 1_200, height: 760)

    // MARK: ContentView

    func testContentViewEmpty() async throws {
        let demo = try await DemoEnvironment.make(withAccounts: false)
        try await renderAndAssert(ContentView().environment(demo.container),
                                  name: "ContentView_empty", size: windowSize, shows: ["No Account Selected"])
    }

    func testContentViewPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.openPhotosBucket()
        try await renderAndAssert(ContentView().environment(demo.container),
                                  name: "ContentView_populated", size: windowSize,
                                  shows: ["report.pdf", "holiday"])
    }

    func testContentViewError() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.browser.fail(with: .networkUnavailable)
        await demo.openPhotosBucket()
        try await renderAndAssert(ContentView().environment(demo.container),
                                  name: "ContentView_error", size: windowSize, shows: ["Network unavailable"])
    }

    // MARK: Sidebar

    func testSidebarEmpty() async throws {
        let demo = try await DemoEnvironment.make(withAccounts: false)
        try await renderAndAssert(sidebar(demo), name: "SidebarView_empty", size: sidebarSize, shows: ["Add Account", "Mounted Drives"])
    }

    func testSidebarPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(sidebar(demo), name: "SidebarView_populated", size: sidebarSize,
                                  shows: ["Demo AWS", "Demo Azure"])
    }

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

    func testBucketListEmpty() async throws {
        let demo = try await DemoEnvironment.make(withAccounts: false)
        demo.container.browserViewModel.account = demo.aws
        try await renderAndAssert(bucketList(demo), name: "BucketListView_empty", shows: ["No Buckets"])
    }

    func testBucketListPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.container.browserViewModel.openAccount(demo.aws)
        try await renderAndAssert(bucketList(demo), name: "BucketListView_populated",
                                  shows: ["photos-2026", "backups", "website-assets"])
    }

    func testBucketListError() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.browser.fail(with: .authenticationFailed)
        await demo.container.browserViewModel.openAccount(demo.aws)
        try await renderAndAssert(bucketList(demo), name: "BucketListView_error", shows: ["Authentication failed"])
    }

    private func bucketList(_ demo: DemoEnvironment) -> some View {
        BucketListView(viewModel: demo.container.browserViewModel).environment(demo.container)
    }

    // MARK: Object list

    func testObjectListEmpty() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.container.browserViewModel.openAccount(demo.aws)
        await demo.container.browserViewModel.openBucket("website-assets")
        try await renderAndAssert(objectList(demo), name: "ObjectListView_empty", shows: ["Empty Folder", "Drag files here"])
    }

    func testObjectListPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.openPhotosBucket()
        try await renderAndAssert(objectList(demo), name: "ObjectListView_populated",
                                  shows: ["holiday", "invoices", "readme.txt", "report.pdf"])
    }

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

    func testObjectDetailEmpty() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.openPhotosBucket()
        try await renderAndAssert(objectDetail(demo), name: "ObjectDetailView_empty", size: detailSize,
                                  shows: ["Select an object to see its details"])
    }

    func testObjectDetailPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.openPhotosBucket()
        demo.container.browserViewModel.selection = ["report.pdf", "readme.txt"]
        try await renderAndAssert(objectDetail(demo), name: "ObjectDetailView_populated", size: detailSize,
                                  shows: ["2 objects"])
    }

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

    func testBreadcrumbsRoot() async throws {
        let demo = try await DemoEnvironment.make()
        await demo.openPhotosBucket()
        try await renderAndAssert(BreadcrumbBar(viewModel: demo.container.browserViewModel),
                                  name: "BreadcrumbBar_root", size: CGSize(width: 700, height: 44), shows: ["photos-2026"])
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

    func testTransferListEmpty() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(TransferListView(viewModel: demo.container.transferQueueViewModel),
                                  name: "TransferListView_empty", shows: ["No Transfers"])
    }

    func testTransferListPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        demo.container.transferQueueViewModel.tasks = demoTransfers(demo, includeFailure: false)
        try await renderAndAssert(TransferListView(viewModel: demo.container.transferQueueViewModel),
                                  name: "TransferListView_populated", shows: ["beach.jpg", "report.pdf"])
    }

    func testTransferListError() async throws {
        let demo = try await DemoEnvironment.make()
        demo.container.transferQueueViewModel.tasks = demoTransfers(demo, includeFailure: true)
        try await renderAndAssert(TransferListView(viewModel: demo.container.transferQueueViewModel),
                                  name: "TransferListView_error", shows: ["sunset.jpg", "Network unavailable"])
    }

    func testMenuBarEmpty() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(MenuBarContent().environment(demo.container),
                                  name: "MenuBarContent_empty", size: menuSize, shows: ["Nothing in flight"])
    }

    func testMenuBarPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        demo.container.transferQueueViewModel.tasks = demoTransfers(demo, includeFailure: true)
        try await renderAndAssert(MenuBarContent().environment(demo.container),
                                  name: "MenuBarContent_populated", size: menuSize, shows: ["holiday/beach.jpg"])
    }

    private let menuSize = CGSize(width: 340, height: 420)

    private func demoTransfers(_ demo: DemoEnvironment, includeFailure: Bool) -> [TransferTask] {
        let folder = FileManager.default.temporaryDirectory
        var tasks = [
            TransferTask(direction: .upload, accountID: demo.aws.id, bucket: "photos-2026", key: "holiday/beach.jpg",
                         localURL: folder.appending(path: "beach.jpg"),
                         state: .running(bytesTransferred: 1_200_000, totalBytes: 2_400_000),
                         startedAt: DemoEnvironment.referenceDate),
            TransferTask(direction: .download, accountID: demo.aws.id, bucket: "photos-2026", key: "report.pdf",
                         localURL: folder.appending(path: "report.pdf"), state: .completed,
                         startedAt: DemoEnvironment.referenceDate)
        ]
        if includeFailure {
            tasks.append(TransferTask(direction: .upload, accountID: demo.aws.id, bucket: "photos-2026",
                                      key: "holiday/sunset.jpg", localURL: folder.appending(path: "sunset.jpg"),
                                      state: .failed(message: "Network unavailable."),
                                      startedAt: DemoEnvironment.referenceDate))
        }
        return tasks
    }
}
