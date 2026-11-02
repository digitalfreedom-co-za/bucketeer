//
//  SyncEngineSchedulingTests.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import XCTest
import SwiftData
import BucketeerCore

/// Business rules for when a sync job may start: the entitlement gate,
/// on-launch jobs, interval schedules, and restarting a cancelled job.
/// Everything runs on in-memory stores and the in-memory object store.
final class SyncEngineSchedulingTests: XCTestCase {

    func testRunIsRefusedWithoutEntitlementAndSaysWhy() async throws {
        let fixture = try await Fixture(authorized: false, schedule: .manual)
        await fixture.engine.runNow(id: fixture.job.id)

        let status = try await fixture.firstStatus { $0.phase == .failed }
        XCTAssertEqual(status.message, "Running sync jobs requires Bucketeer Pro.")
    }

    func testReloadDoesNotStartOnLaunchJobsButLaunchDoes() async throws {
        let fixture = try await Fixture(authorized: true, schedule: .onLaunch)
        try await fixture.engine.reload()
        try await Task.sleep(for: .milliseconds(300))
        let afterReload = await fixture.collectedStatuses()
        XCTAssertNil(afterReload[fixture.job.id], "reload() must not run on-launch jobs")

        await fixture.engine.runLaunchJobs()
        _ = try await fixture.firstStatus { _ in true }
    }

    func testIntervalJobRunsOnItsOwn() async throws {
        let fixture = try await Fixture(authorized: true, schedule: .interval(seconds: 1))
        try await fixture.engine.reload()
        _ = try await fixture.firstStatus(timeout: .seconds(4)) { _ in true }
        await fixture.engine.shutdown()
    }

    func testCancelledRunWindingDownLeavesItsRestartAlone() async throws {
        let fixture = try await Fixture(authorized: true, schedule: .manual)
        await fixture.browser.put(bucket: "source", key: "report.pdf", size: 1)
        await fixture.browser.holdNextCopy()
        await fixture.engine.runNow(id: fixture.job.id)
        try await fixture.waitUntil { await fixture.browser.isHoldingCopy }

        await fixture.engine.cancel(id: fixture.job.id)
        await fixture.engine.runNow(id: fixture.job.id)
        _ = try await fixture.firstStatus { $0.phase == .finished }
        await fixture.browser.releaseHeldCopy()
        try await Task.sleep(for: .milliseconds(300))

        let status = await fixture.collectedStatuses()[fixture.job.id]
        XCTAssertEqual(status?.phase, .finished, "the cancelled run must not overwrite the restart's status")
    }
}

private struct Fixture {
    let engine: SyncEngine
    let job: SyncJob
    let browser: InMemoryS3Browser
    private let collector: StatusCollector

    init(authorized: Bool, schedule: SyncSchedule) async throws {
        let container = try SharedStore.makeInMemoryContainer()
        let accountStore = AccountStore(modelContainer: container)
        let jobStore = SyncJobStore(modelContainer: container)
        let account = S3Account(name: "Demo", provider: .awsS3)
        try await accountStore.upsert(account)
        browser = InMemoryS3Browser()
        await browser.addBucket("source")
        await browser.addBucket("destination")
        job = SyncJob(
            name: "Job",
            source: .s3(accountID: account.id, bucket: "source", prefix: ""),
            destination: .s3(accountID: account.id, bucket: "destination", prefix: ""),
            schedule: schedule
        )
        try await jobStore.upsert(job)
        engine = SyncEngine(
            accountStore: accountStore,
            jobStore: jobStore,
            browser: browser,
            transferManager: TransferManager(factory: S3ClientFactory(keychainStore: InMemoryKeychain())),
            isAuthorized: { authorized }
        )
        if case .manual = schedule {
            try await engine.reload()
        }
        collector = StatusCollector(stream: engine.statuses)
    }

    func collectedStatuses() async -> [UUID: SyncJobStatus] {
        await collector.latest
    }

    func firstStatus(
        timeout: Duration = .seconds(2),
        where predicate: @Sendable (SyncJobStatus) -> Bool
    ) async throws -> SyncJobStatus {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let match = await collector.latest[job.id], predicate(match) { return match }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("no matching status for the job within \(timeout)")
        throw CancellationError()
    }

    func waitUntil(_ condition: @Sendable () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("condition not met within 2 seconds")
        throw CancellationError()
    }
}

/// Keeps the newest status per job from the engine's stream.
private actor StatusCollector {
    private(set) var latest: [UUID: SyncJobStatus] = [:]
    private var pump: Task<Void, Never>?

    init(stream: AsyncStream<[SyncJobStatus]>) {
        pump = nil
        Task { await self.start(stream) }
    }

    private func start(_ stream: AsyncStream<[SyncJobStatus]>) {
        pump = Task { [weak self] in
            for await snapshot in stream {
                await self?.store(snapshot)
            }
        }
    }

    private func store(_ snapshot: [SyncJobStatus]) {
        for status in snapshot { latest[status.jobID] = status }
    }
}
