//
//  SyncRenderTests.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import XCTest
import SwiftUI
import BucketeerCore

@MainActor
final class SyncRenderTests: XCTestCase {
    private let sheetSize = CGSize(width: 620, height: 720)

    func testSyncJobListPopulated() async throws {
        let demo = try await DemoEnvironment.make()
        try await demo.container.syncJobStore.upsert(nightlyJob(demo))
        await demo.container.syncJobListViewModel.refresh()
        try await renderAndAssert(list(demo), name: "SyncJobListView_populated",
                                  shows: ["Nightly photos", "Mirror", "12 ok / 0 failed"])
    }

    private func list(_ demo: DemoEnvironment) -> some View {
        SyncJobListView(viewModel: demo.container.syncJobListViewModel).environment(demo.container)
    }

    // MARK: Detail window

    /// A job whose account no longer exists fails in the real engine;
    /// the window must show that status.
    func testSyncJobDetailError() async throws {
        let demo = try await DemoEnvironment.make()
        var job = nightlyJob(demo)
        job.source = .s3(accountID: UUID(), bucket: "gone", prefix: "")
        try await demo.container.syncJobStore.upsert(job)
        try await demo.container.syncEngine.reload()
        await demo.container.syncEngine.runNow(id: job.id)
        try await renderAndAssert(SyncJobDetailWindow(jobID: job.id).environment(demo.container),
                                  name: "SyncJobDetailWindow_error", size: sheetSize,
                                  shows: ["Nightly photos backup", "Failed"])
    }

    private func nightlyJob(_ demo: DemoEnvironment) -> SyncJob {
        SyncJob(
            id: UUID(uuidString: "6F0C1E2A-3B4D-4E5F-8A9B-0C1D2E3F4A5B")!,
            name: "Nightly photos backup",
            mode: .mirror,
            source: .s3(accountID: demo.aws.id, bucket: "photos-2026", prefix: "holiday/"),
            destination: .s3(accountID: demo.azure.id, bucket: "backups", prefix: "photos/"),
            excludeGlobs: ["*.tmp"],
            deletePropagation: true,
            schedule: .interval(seconds: 3_600),
            lastRunAt: DemoEnvironment.referenceDate,
            lastRunSummary: "12 ok / 0 failed / 12 planned"
        )
    }
}
