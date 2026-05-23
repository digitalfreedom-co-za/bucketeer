//
//  SyncEngine.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import BucketeerCore

/// Runs sync jobs — recursively diffs source vs destination, executes
/// the planned transfers, then records the outcome. Single actor so
/// per-job state mutations stay consistent under concurrent reads from
/// the UI status stream.
///
/// Design choices for v1:
/// - Recursive listing walks the source/destination one prefix at a
///   time using the existing delimiter listing. A flat lister would be
///   faster on huge datasets; tracked for v1.1.
/// - Cross-provider transfers stage through a tempdir file. Same-account
///   transfers use server-side copy when both source and destination
///   live on the same `accountID`.
/// - Mirror delete-propagation defaults to off. When on, deletes are
///   applied after additions/updates so we do not lose data on a
///   transient comparison error.
actor SyncEngine {
    private let accountStore: any AccountStoring
    private let jobStore: any SyncJobStoring
    private let browser: any S3Browsing
    private let transferManager: TransferManager

    /// Public status stream. Snapshots are pushed on every phase change
    /// or progress tick. Consumers replace, not merge.
    nonisolated let statuses: AsyncStream<[SyncJobStatus]>
    private let continuation: AsyncStream<[SyncJobStatus]>.Continuation

    private var current: [UUID: SyncJobStatus] = [:]
    private var runners: [UUID: Task<Void, Never>] = [:]
    private var jobs: [UUID: SyncJob] = [:]
    /// Per-sync-job: the transfer-manager IDs the engine has handed off
    /// to the queue. Used to actively cancel in-flight uploads /
    /// downloads when the sync job is cancelled, instead of just
    /// cancelling the orchestrating task and letting the transfers keep
    /// running.
    private var activeTransferIDs: [UUID: Set<UUID>] = [:]

    init(
        accountStore: any AccountStoring,
        jobStore: any SyncJobStoring,
        browser: any S3Browsing,
        transferManager: TransferManager
    ) {
        self.accountStore = accountStore
        self.jobStore = jobStore
        self.browser = browser
        self.transferManager = transferManager
        let (stream, continuation) = AsyncStream<[SyncJobStatus]>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.statuses = stream
        self.continuation = continuation
    }

    deinit { continuation.finish() }

    // MARK: - Registration

    /// Refresh the in-memory job table from the persistent store. Called
    /// at app launch and every time a job is added / edited / deleted.
    func reload() async throws {
        let all = try await jobStore.all()
        jobs.removeAll()
        for job in all { jobs[job.id] = job }
        publish()
        // Kick off any on-launch jobs that are enabled. Interval and
        // manual jobs are not started here.
        for job in all where job.enabled && job.schedule == .onLaunch {
            await runNow(id: job.id)
        }
    }

    // MARK: - Job control

    /// Run the job immediately. Idempotent — calling while already
    /// running is a no-op (returns the existing runner).
    func runNow(id: UUID) async {
        guard let job = jobs[id], runners[id] == nil else { return }
        updateStatus(id: id, phase: .planning, message: nil)
        let task = Task { [weak self] in
            _ = await self?.execute(job: job)
        }
        runners[id] = task
    }

    /// Cancel a running job. Idempotent. Cancels the orchestrating
    /// task **and** every transfer-manager task the engine has handed
    /// to the queue for this job — Codex review #3.
    func cancel(id: UUID) async {
        runners[id]?.cancel()
        runners[id] = nil
        if let ids = activeTransferIDs[id] {
            for transferID in ids {
                await transferManager.cancel(id: transferID)
            }
        }
        activeTransferIDs.removeValue(forKey: id)
        if current[id] != nil {
            updateStatus(id: id, phase: .cancelled, message: nil)
        }
    }

    private func registerActiveTransfer(jobID: UUID, transferID: UUID) {
        activeTransferIDs[jobID, default: []].insert(transferID)
    }

    private func unregisterActiveTransfer(jobID: UUID, transferID: UUID) {
        activeTransferIDs[jobID]?.remove(transferID)
    }

    // MARK: - Execution

    private func execute(job: SyncJob) async {
        let start = Date()
        defer { runners[job.id] = nil }

        let accounts: (source: S3Account, destination: S3Account)
        do {
            accounts = try await resolveAccounts(for: job)
        } catch {
            updateStatus(
                id: job.id,
                phase: .failed,
                message: bucketeerError(error).errorDescription
            )
            return
        }

        let sourceList: [S3Object]
        let destList: [S3Object]
        do {
            async let s = listAllObjects(account: accounts.source, endpoint: job.source)
            async let d = listAllObjects(account: accounts.destination, endpoint: job.destination)
            sourceList = try await s
            destList = try await d
        } catch {
            updateStatus(
                id: job.id,
                phase: .failed,
                message: bucketeerError(error).errorDescription
            )
            return
        }

        let plan = SyncPlanner.makePlan(
            job: job,
            source: sourceList,
            destination: destList
        )
        let planned = plan.upserts.count + (job.mode == .mirror && job.deletePropagation ? plan.deletes.count : 0)
        updateStatus(
            id: job.id,
            phase: .running,
            planned: planned,
            startedAt: start
        )

        var completed = 0
        var failed = 0
        /// Tracks which entries actually succeeded so move-mode does
        /// not delete the source for failed upserts (Codex blocker #1).
        var successfulEntries: [SyncPlanner.PlanEntry] = []

        // Upserts: copy or transfer per entry.
        for entry in plan.upserts {
            if Task.isCancelled {
                updateStatus(id: job.id, phase: .cancelled)
                return
            }
            do {
                try await execute(
                    upsert: entry,
                    job: job,
                    source: accounts.source,
                    destination: accounts.destination
                )
                completed += 1
                successfulEntries.append(entry)
            } catch {
                failed += 1
            }
            updateStatus(
                id: job.id,
                phase: .running,
                planned: planned,
                completed: completed,
                failed: failed
            )
        }

        // Mirror deletes (only when explicitly enabled).
        if job.mode == .mirror && job.deletePropagation {
            for key in plan.deletes {
                if Task.isCancelled { break }
                do {
                    try await browser.delete(
                        account: accounts.destination,
                        bucket: job.destination.bucket,
                        keys: [key]
                    )
                    completed += 1
                } catch {
                    failed += 1
                }
                updateStatus(
                    id: job.id,
                    phase: .running,
                    planned: planned,
                    completed: completed,
                    failed: failed
                )
            }
        }

        // Move mode: delete the source **only** for entries whose
        // upsert succeeded (Codex blocker #1 — failed copies must not
        // trigger source deletes), and only if the job was not
        // cancelled mid-flight.
        if job.mode == .move && !Task.isCancelled {
            for entry in successfulEntries where !Task.isCancelled {
                try? await browser.delete(
                    account: accounts.source,
                    bucket: job.source.bucket,
                    keys: [entry.sourceKey]
                )
            }
        }

        let summary = "\(completed) ok / \(failed) failed / \(planned) planned"
        updateStatus(
            id: job.id,
            phase: failed > 0 ? .failed : .finished,
            planned: planned,
            completed: completed,
            failed: failed,
            message: summary
        )
        try? await jobStore.touchLastRun(id: job.id, at: Date(), summary: summary)
        if var refreshed = jobs[job.id] {
            refreshed.lastRunAt = Date()
            refreshed.lastRunSummary = summary
            jobs[job.id] = refreshed
        }
    }

    // MARK: - Execute single entry

    private func execute(
        upsert entry: SyncPlanner.PlanEntry,
        job: SyncJob,
        source: S3Account,
        destination: S3Account
    ) async throws {
        if source.id == destination.id {
            // Same account → server-side copy is cheap and atomic-ish.
            try await browser.copy(
                account: source,
                fromBucket: job.source.bucket,
                fromKey: entry.sourceKey,
                toBucket: job.destination.bucket,
                toKey: entry.destinationKey,
                metadata: nil
            )
            return
        }
        // Cross-account → temp staging, then upload. Track both halves
        // as "active transfers" for the job so a user-initiated cancel
        // can tear them down (Codex review #3) and use the new
        // `awaitCompletion(id:)` actor API instead of polling the
        // public `tasks` stream (Codex review #2).
        let staging = stagingURL(for: entry.sourceKey)
        let downloadID = await transferManager.enqueueDownload(
            account: source,
            bucket: job.source.bucket,
            key: entry.sourceKey,
            localURL: staging
        )
        registerActiveTransfer(jobID: job.id, transferID: downloadID)
        defer {
            unregisterActiveTransfer(jobID: job.id, transferID: downloadID)
            try? FileManager.default.removeItem(at: staging)
        }
        try terminalToError(await transferManager.awaitCompletion(id: downloadID))

        let uploadID = await transferManager.enqueueUpload(
            account: destination,
            bucket: job.destination.bucket,
            key: entry.destinationKey,
            localURL: staging,
            contentType: nil
        )
        registerActiveTransfer(jobID: job.id, transferID: uploadID)
        defer { unregisterActiveTransfer(jobID: job.id, transferID: uploadID) }
        try terminalToError(await transferManager.awaitCompletion(id: uploadID))
    }

    private nonisolated func terminalToError(_ state: TransferState) throws {
        switch state {
        case .completed:
            return
        case .failed(let message):
            throw BucketeerError.providerError(statusCode: 0, message: message)
        case .cancelled:
            throw BucketeerError.cancelled
        case .queued, .running:
            // awaitCompletion only returns terminal states by contract;
            // a non-terminal value here is a logic bug in TransferManager.
            throw BucketeerError.unknown(message: "Transfer returned a non-terminal state from awaitCompletion.")
        }
    }

    private func stagingURL(for sourceKey: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "BucketeerSync", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = UUID().uuidString + "-" + (sourceKey.split(separator: "/").last.map(String.init) ?? "object")
        return dir.appending(path: filename)
    }

    // MARK: - Recursive listing

    /// Recursive list of every non-folder object under `endpoint` — walks
    /// the existing delimiter listing one prefix at a time so the
    /// existing protocol surface keeps working. v1.1 will replace this
    /// with a flat-listing primitive on `S3Browsing` to avoid the
    /// per-prefix request fan-out.
    private func listAllObjects(account: S3Account, endpoint: SyncEndpoint) async throws -> [S3Object] {
        var output: [S3Object] = []
        var queue: [String] = [endpoint.prefix]
        while !queue.isEmpty {
            let prefix = queue.removeFirst()
            var token: String? = nil
            repeat {
                let page = try await browser.listObjects(
                    account: account,
                    bucket: endpoint.bucket,
                    prefix: prefix,
                    continuationToken: token
                )
                for object in page.objects {
                    if object.isFolder {
                        queue.append(object.key)
                    } else {
                        output.append(object)
                    }
                }
                token = page.continuationToken
                if !page.hasMore { token = nil }
            } while token != nil
        }
        return output
    }

    private func resolveAccounts(for job: SyncJob) async throws -> (source: S3Account, destination: S3Account) {
        let all = try await accountStore.all()
        guard let source = all.first(where: { $0.id == job.source.accountID }) else {
            throw BucketeerError.unknown(message: "Source account no longer exists.")
        }
        guard let destination = all.first(where: { $0.id == job.destination.accountID }) else {
            throw BucketeerError.unknown(message: "Destination account no longer exists.")
        }
        return (source, destination)
    }

    // MARK: - Status

    private func updateStatus(
        id: UUID,
        phase: SyncJobStatus.Phase,
        planned: Int? = nil,
        completed: Int? = nil,
        failed: Int? = nil,
        startedAt: Date? = nil,
        message: String? = nil
    ) {
        var status = current[id] ?? SyncJobStatus(
            jobID: id,
            phase: phase,
            planned: 0,
            completed: 0,
            failed: 0,
            startedAt: nil,
            message: nil
        )
        status.phase = phase
        if let planned { status.planned = planned }
        if let completed { status.completed = completed }
        if let failed { status.failed = failed }
        if let startedAt { status.startedAt = startedAt }
        status.message = message ?? status.message
        current[id] = status
        publish()
    }

    private func publish() {
        let snapshot = Array(current.values)
        continuation.yield(snapshot)
    }

    private func bucketeerError(_ error: Error) -> BucketeerError {
        if let e = error as? BucketeerError { return e }
        return .unknown(message: error.localizedDescription)
    }
}
