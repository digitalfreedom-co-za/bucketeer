//
//  SettingsRenderTests.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import XCTest
import SwiftUI
import BucketeerCore

/// Settings, trash, activity log and the informational windows.
@MainActor
final class SettingsRenderTests: XCTestCase {
    private let paneSize = CGSize(width: 760, height: 560)

    func testSettingsGeneral() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(SettingsView().environment(demo.container), name: "SettingsView_general",
                                  size: paneSize, shows: ["Run Bucketeer in the menu bar"])
    }

    // MARK: Encryption keys

    func testEncryptionKeysEmpty() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(EncryptionKeysView().environment(demo.container),
                                  name: "EncryptionKeysView_empty", size: paneSize, shows: ["No encryption keys"])
    }

    func testEncryptionKeysPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        let viewModel = demo.container.encryptionKeysViewModel
        // Staged rather than created: a real key would be written to the Keychain.
        try await renderAndAssert(EncryptionKeysView().environment(demo.container),
                                  name: "EncryptionKeysView_populated", size: paneSize, shows: ["Photos key", "photos-2026"],
                                  afterAppear: {
            viewModel.accounts = demo.accounts
            viewModel.keys = [BucketEncryptionKey(label: "Photos key", accountID: demo.aws.id, bucket: "photos-2026",
                                                  createdAt: DemoEnvironment.referenceDate)]
        })
    }

    func testEncryptionKeysError() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(EncryptionKeysView().environment(demo.container),
                                  name: "EncryptionKeysView_error", size: paneSize,
                                  shows: ["Keychain operation failed (status -25308)"],
                                  afterAppear: { demo.container.encryptionKeysViewModel.error = .keychainFailure(status: -25308) })
    }

    func testHardwareKey() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(HardwareKeyView().environment(demo.container),
                                  name: "HardwareKeyView_default", size: paneSize, shows: ["Detected hardware"])
    }

    // MARK: Auto-tag rules

    func testAutoTagRulesEmpty() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(AutoTagRulesView().environment(demo.container),
                                  name: "AutoTagRulesView_empty", size: paneSize, shows: ["No rules yet"])
    }

    func testAutoTagRulesPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        try await demo.container.autoTagStore.upsert(
            AutoTagRule(name: "Tag invoices", filenameGlob: "invoices/*.pdf", tags: ["type": "invoice"]))
        try await demo.container.autoTagStore.upsert(
            AutoTagRule(name: "Images", enabled: false, mimePrefix: "image/", userMetadata: ["source": "camera"]))
        try await renderAndAssert(AutoTagRulesView().environment(demo.container),
                                  name: "AutoTagRulesView_populated", size: paneSize, shows: ["Tag invoices", "Images"])
    }

    func testAutoTagRulesError() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(AutoTagRulesView().environment(demo.container),
                                  name: "AutoTagRulesView_error", size: paneSize, shows: ["disk full"],
                                  afterAppear: { demo.container.autoTagRulesViewModel.error = .persistenceFailure(message: "disk full") })
    }

    // MARK: Trash

    func testTrashEmpty() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(TrashView().environment(demo.container), name: "TrashView_empty", shows: ["Trash is empty"])
    }

    func testTrashPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        let viewModel = demo.container.trashViewModel
        try await renderAndAssert(TrashView().environment(demo.container), name: "TrashView_populated",
                                  shows: ["draft.docx"], afterAppear: {
            viewModel.accounts = demo.accounts
            viewModel.items = [
                TrashedItem(accountID: demo.aws.id, accountName: "Demo AWS", bucket: "photos-2026", key: "old/draft.docx",
                            size: 52_000, contentType: nil, etag: nil, deletedAt: DemoEnvironment.referenceDate,
                            expiresAt: DemoEnvironment.referenceDate.addingTimeInterval(30 * 86_400), cacheStatus: .cached)
            ]
            viewModel.totalCount = 1
        })
    }

    func testTrashError() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(TrashView().environment(demo.container), name: "TrashView_error", shows: ["disk full"],
                                  afterAppear: { demo.container.trashViewModel.error = .persistenceFailure(message: "disk full") })
    }

    // MARK: Activity log

    func testActivityLogEmpty() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(ActivityLogView().environment(demo.container), name: "ActivityLogView_empty", shows: ["No activity recorded yet"])
    }

    func testActivityLogPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        for entry in [
            ActivityEntry(kind: .upload, status: .success, createdAt: DemoEnvironment.referenceDate,
                          accountID: demo.aws.id, accountName: "Demo AWS", bucket: "photos-2026",
                          key: "holiday/beach.jpg", byteCount: 2_400_000),
            ActivityEntry(kind: .download, status: .failure, createdAt: DemoEnvironment.referenceDate,
                          accountID: demo.aws.id, accountName: "Demo AWS", bucket: "photos-2026",
                          key: "report.pdf", errorMessage: "Network unavailable.")
        ] {
            await demo.container.activityLog.record(entry)
        }
        try await renderAndAssert(ActivityLogView().environment(demo.container), name: "ActivityLogView_populated",
                                  shows: ["beach.jpg", "report.pdf"])
    }

    func testActivityLogError() async throws {
        let demo = try await DemoEnvironment.make()
        try await renderAndAssert(ActivityLogView().environment(demo.container), name: "ActivityLogView_error",
                                  shows: ["disk full"],
                                  afterAppear: { demo.container.activityLogViewModel.error = .persistenceFailure(message: "disk full") })
    }

    // MARK: Informational windows

    func testAboutWindow() async throws {
        try await renderAndAssert(AboutWindow(), name: "AboutWindow_default", size: CGSize(width: 640, height: 560),
                                  shows: ["Bucketeer"])
    }

    func testHelpWindow() async throws {
        try await renderAndAssert(HelpWindow(), name: "HelpWindow_default", size: CGSize(width: 720, height: 620), shows: ["Quick Start"])
    }

    func testMarkdownView() async throws {
        try await renderAndAssert(MarkdownView(text: "# Heading\n\nSome **bold** text and a [link](https://example.com).\n\n- one\n- two"),
                                  name: "MarkdownView_populated", size: CGSize(width: 520, height: 300),
                                  shows: ["Heading", "bold", "one"])
    }
}
