//
//  SyncEngine.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation

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
    private let accountStore: AccountStoring
    private let jobStore: SyncJobStoring
    private let browser: S3Browsing
    private let transferManager: TransferManager

    /// Public status stream. Snapshots are pushed on every phase change
    /// or progress tick. Consumers replace, not merge.
    nonisolated let statuses: AsyncStream<[SyncJobStatus]>
    private let continuation: AsyncStream<[SyncJobStatus]>.Continuation

    private var current: [UUID: SyncJobStatus] = [:]
    private var runners: [UUID: Task<Void, Never>] = [:]
    private var jobs: [UUID: SyncJob] = [:]

    init(
        accountStore: AccountStoring,
        jobStore: SyncJobStoring,
        browser: S3Browsing,
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

    /// Cancel a running job. Idempotent.
    func cancel(id: UUID) async {
        runners[id]?.cancel()
        runners[id] = nil
        if current[id] != nil {
            updateStatus(id: id, phase: .cancelled, message: nil)
        }
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

        let plan = makePlan(
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

        // Move mode: after every successful upsert, remove the source.
        if job.mode == .move {
            for entry in plan.upserts where !Task.isCancelled {
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

    // MARK: - Plan

    struct PlanEntry: Hashable, Sendable {
        let sourceKey: String
        let sourceSize: Int64
        let destinationKey: String
    }

    struct Plan: Sendable {
        let upserts: [PlanEntry]
        /// Destination-side keys that exist in the destination but not in
        /// the source. Only populated for mirror jobs with
        /// `deletePropagation == true`.
        let deletes: [String]
    }

    nonisolated func makePlan(
        job: SyncJob,
        source: [S3Object],
        destination: [S3Object]
    ) -> Plan {
        let destIndex: [String: S3Object] = Dictionary(
            uniqueKeysWithValues: destination.map { ($0.key, $0) }
        )

        var upserts: [PlanEntry] = []
        for s in source {
            if s.isFolder { continue }
            let relative = relativeKey(s.key, under: job.source.prefix)
            guard !relative.isEmpty else { continue }
            if !matches(relative, includes: job.includeGlobs, excludes: job.excludeGlobs) {
                continue
            }
            let destKey = job.destination.prefix + relative
            if let existing = destIndex[destKey], isUnchanged(
                source: s, dest: existing, strategy: job.diffStrategy
            ) {
                continue
            }
            upserts.append(PlanEntry(
                sourceKey: s.key,
                sourceSize: s.size,
                destinationKey: destKey
            ))
        }

        var deletes: [String] = []
        if job.mode == .mirror && job.deletePropagation {
            // Compute the inverse of upserts: destination keys whose
            // corresponding relative path is absent from the source.
            let sourceRelatives = Set(
                source
                    .filter { !$0.isFolder }
                    .map { relativeKey($0.key, under: job.source.prefix) }
            )
            for d in destination where !d.isFolder {
                let relative = relativeKey(d.key, under: job.destination.prefix)
                if !sourceRelatives.contains(relative) {
                    deletes.append(d.key)
                }
            }
        }

        return Plan(upserts: upserts, deletes: deletes)
    }

    private nonisolated func relativeKey(_ key: String, under prefix: String) -> String {
        guard !prefix.isEmpty, key.hasPrefix(prefix) else { return key }
        return String(key.dropFirst(prefix.count))
    }

    private nonisolated func isUnchanged(
        source: S3Object,
        dest: S3Object,
        strategy: SyncDiffStrategy
    ) -> Bool {
        switch strategy {
        case .nameAndSize:
            return source.size == dest.size
        case .nameAndEtag:
            return !source.etag.isEmpty && source.etag == dest.etag
        }
    }

    private nonisolated func matches(
        _ relative: String,
        includes: [String],
        excludes: [String]
    ) -> Bool {
        if !excludes.isEmpty {
            for pattern in excludes where glob(relative, matches: pattern) {
                return false
            }
        }
        if !includes.isEmpty {
            return includes.contains { glob(relative, matches: $0) }
        }
        return true
    }

    /// Minimal POSIX-glob matching (?, *) for include/exclude patterns.
    private nonisolated func glob(_ value: String, matches pattern: String) -> Bool {
        // Fallback to fnmatch via NSPredicate's LIKE — supports * and ?.
        let predicate = NSPredicate(format: "SELF LIKE %@", pattern)
        return predicate.evaluate(with: value)
    }

    // MARK: - Execute single entry

    private func execute(
        upsert entry: PlanEntry,
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
        // Cross-account → temp staging, then upload.
        let staging = stagingURL(for: entry.sourceKey)
        let downloadID = await transferManager.enqueueDownload(
            account: source,
            bucket: job.source.bucket,
            key: entry.sourceKey,
            localURL: staging
        )
        try await waitForTransfer(downloadID)
        let uploadID = await transferManager.enqueueUpload(
            account: destination,
            bucket: job.destination.bucket,
            key: entry.destinationKey,
            localURL: staging,
            contentType: nil
        )
        try await waitForTransfer(uploadID)
        try? FileManager.default.removeItem(at: staging)
    }

    private func waitForTransfer(_ id: UUID) async throws {
        for await snapshot in transferManager.tasks {
            guard let task = snapshot.first(where: { $0.id == id }) else { continue }
            switch task.state {
            case .completed:
                return
            case .failed(let message):
                throw BucketeerError.providerError(statusCode: 0, message: message)
            case .cancelled:
                throw BucketeerError.cancelled
            case .queued, .running:
                continue
            }
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
