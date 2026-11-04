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
    /// One entry per running job. The token identifies the run: only
    /// the run that owns the slot may publish status or persist its
    /// summary, so a cancelled run winding down can neither clear the
    /// slot of a newer run nor overwrite its status.
    private struct Runner {
        let token: UUID
        let task: Task<Void, Never>
    }
    private var runners: [UUID: Runner] = [:]
    private var jobs: [UUID: SyncJob] = [:]
    /// Per run token: the transfer-manager IDs the run has handed off
    /// to the queue. Used to actively cancel in-flight uploads /
    /// downloads when the sync job is cancelled, instead of just
    /// cancelling the orchestrating task and letting the transfers keep
    /// running. Keyed by run, not job, so a cancel that resumes after
    /// a restart cannot drop the new run's transfers.
    private var activeTransferIDs: [UUID: Set<UUID>] = [:]
    /// Tokens of cancelled runs, so a transfer that returned from
    /// `enqueue…` *after* the cancel call still gets caught and torn
    /// down — even when a new run of the same job started meanwhile.
    /// Removed when the cancelled run has fully wound down.
    private var cancelledRuns: Set<UUID> = []
    /// Watch-folder events that arrive while
    /// a job is already running used to be dropped (runNow no-ops
    /// when `runners[id] != nil`). Local file changes could then
    /// stay unsynced until a *future* event nudged the watcher
    /// again. The pending-rerun bit fires one immediate re-run as
    /// soon as the current run finishes.
    private var pendingReruns: Set<UUID> = []
    /// Phase 9.10: per-job FSEvents watcher + the Task that pumps the
    /// watcher's debounced AsyncStream into runNow calls. Started on
    /// reload() for jobs with a local source and `.onLocalChange`
    /// schedule; torn down when the job is removed or its schedule
    /// changes to something non-watcher.
    private struct WatcherEntry {
        let watcher: LocalFolderWatcher
        let pumpTask: Task<Void, Never>
        /// The raw bookmark `Data` — used to detect that the user
        /// re-picked the folder. Compares the full bytes rather than
        /// the `Int` hashValue (which collides) with the full
        /// bytes; equality is the only correct identity check.
        let bookmarkData: Data
        /// The resolved URL whose security scope was started when the
        /// watcher was created. Held for the watcher's whole lifetime
        /// so FSEvents keeps access to the folder; released in
        /// `teardown()`.
        let scopedURL: URL?

        func teardown() {
            pumpTask.cancel()
            watcher.stop()
            scopedURL?.stopAccessingSecurityScopedResource()
        }
    }
    private var watchers: [UUID: WatcherEntry] = [:]
    private struct IntervalTimer {
        let seconds: Int
        let task: Task<Void, Never>
    }
    private var intervalTimers: [UUID: IntervalTimer] = [:]

    private let activityLog: (any ActivityLogging)?
    /// Entitlement check run before every job start — manual, on-launch,
    /// interval and watch-folder triggers alike.
    private let isAuthorized: @Sendable () async -> Bool
    /// Decides whether a same-account copy may stay server-side.
    private let encryptionGate: BucketEncryptionGate?

    init(
        accountStore: any AccountStoring,
        jobStore: any SyncJobStoring,
        browser: any S3Browsing,
        transferManager: TransferManager,
        activityLog: (any ActivityLogging)? = nil,
        encryptionGate: BucketEncryptionGate? = nil,
        isAuthorized: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.encryptionGate = encryptionGate
        self.accountStore = accountStore
        self.jobStore = jobStore
        self.browser = browser
        self.transferManager = transferManager
        self.activityLog = activityLog
        self.isAuthorized = isAuthorized
        let (stream, continuation) = AsyncStream<[SyncJobStatus]>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.statuses = stream
        self.continuation = continuation
    }

    deinit { continuation.finish() }

    /// Tear down every FSEvents watcher + pump task. Actor deinit can't reach actor-isolated state
    /// in Swift 6, so we expose an explicit shutdown the host
    /// calls from its own dealloc path (or from a hot-reload
    /// hook in tests). Idempotent.
    func shutdown() {
        for entry in watchers.values {
            entry.teardown()
        }
        watchers.removeAll()
        intervalTimers.values.forEach { $0.task.cancel() }
        intervalTimers.removeAll()
        runners.values.forEach { $0.task.cancel() }
        runners.removeAll()
        // A rerun bit left set here would fire `runNow` on the
        // already-shut-down engine from the execute() defer.
        pendingReruns.removeAll()
    }

    // MARK: - Registration

    /// Refresh the in-memory job table from the persistent store. Called
    /// at app launch and every time a job is added / edited / deleted.
    func reload() async throws {
        let all = try await jobStore.all()
        jobs.removeAll()
        for job in all { jobs[job.id] = job }
        // Drop statuses of deleted jobs.
        current = current.filter { jobs[$0.key] != nil }
        publish()
        // Reconcile FSEvents watchers for `.onLocalChange` jobs whose
        // source is a local folder. Phase 9.10.
        reconcileLocalChangeWatchers(against: all)
        reconcileIntervalTimers(against: all)
    }

    /// Start every enabled on-launch job. Called once at app launch —
    /// not from `reload()`, which runs after every job edit.
    func runLaunchJobs() async {
        for job in jobs.values where job.enabled && job.schedule == .onLaunch {
            await runNow(id: job.id)
        }
    }

    /// One repeating timer per enabled interval job; restarted when the
    /// interval changes, stopped when the job is gone or rescheduled.
    private func reconcileIntervalTimers(against jobs: [SyncJob]) {
        var keepIDs: Set<UUID> = []
        for job in jobs where job.enabled {
            guard case .interval(let seconds) = job.schedule else { continue }
            keepIDs.insert(job.id)
            if intervalTimers[job.id]?.seconds == seconds { continue }
            intervalTimers.removeValue(forKey: job.id)?.task.cancel()
            let jobID = job.id
            let task = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(seconds))
                    guard !Task.isCancelled else { return }
                    await self?.runNow(id: jobID)
                }
            }
            intervalTimers[job.id] = IntervalTimer(seconds: seconds, task: task)
        }
        for (id, timer) in intervalTimers where !keepIDs.contains(id) {
            timer.task.cancel()
            intervalTimers.removeValue(forKey: id)
        }
    }

    /// Bring the set of running FSEvents watchers in sync with the
    /// current job table. Idempotent — stops watchers whose job was
    /// deleted / disabled / changed schedule, starts new ones for
    /// freshly-eligible jobs, and re-creates a watcher when the
    /// bookmark behind a job changed (i.e. the user re-picked the
    /// folder).
    private func reconcileLocalChangeWatchers(against jobs: [SyncJob]) {
        var keepIDs: Set<UUID> = []
        for job in jobs where job.enabled && job.schedule == .onLocalChange {
            guard case .localFolder(let bookmark, _) = job.source else { continue }
            keepIDs.insert(job.id)
            // Existing watcher with the same bookmark → leave running.
            // Equality on the raw bytes
            // instead of `hashValue`; hashValue collisions would
            // falsely treat an edited bookmark as identical.
            if let existing = watchers[job.id], existing.bookmarkData == bookmark {
                continue
            }
            // Tear down stale watcher (bookmark moved or job edited)
            // before starting a fresh one.
            if let existing = watchers.removeValue(forKey: job.id) {
                existing.teardown()
            }
            guard let (url, _) = try? LocalFolderEnumerator.resolveBookmark(bookmark) else {
                continue
            }
            // Keep the security scope alive for the watcher's whole
            // lifetime — releasing it right after `start()` would leave
            // FSEvents registered on a folder the sandbox no longer
            // grants access to. Balanced in `WatcherEntry.teardown()`.
            let didStartScope = url.startAccessingSecurityScopedResource()
            let watcher = LocalFolderWatcher(rootURL: url, latencySeconds: 3.0)
            guard watcher.start() else {
                if didStartScope { url.stopAccessingSecurityScopedResource() }
                continue
            }
            // Pump the watcher's debounced events into runNow calls.
            // Each event triggers one sync — `runNow` is itself
            // idempotent (guards on `runners[id] == nil`) so an event
            // that lands mid-run is dropped harmlessly.
            let jobID = job.id
            let jobName = job.name
            // Capture for use inside the pump task.
            let pumpActivityLog = self.activityLog
            let pump = Task { [weak self] in
                for await _ in watcher.events {
                    // Phase 13.3 — record the trigger before kicking
                    // off the job so the user can see in the activity
                    // log why a job started even when the run itself
                    // produces zero transfers (e.g. only a touch).
                    if let pumpActivityLog {
                        await pumpActivityLog.record(
                            ActivityEntry(
                                kind: .watchFolderTriggered,
                                status: .info,
                                syncJobID: jobID,
                                syncJobName: jobName
                            )
                        )
                    }
                    await self?.runNow(id: jobID)
                }
            }
            watchers[job.id] = WatcherEntry(
                watcher: watcher,
                pumpTask: pump,
                bookmarkData: bookmark,
                scopedURL: didStartScope ? url : nil
            )
        }
        // Stop every watcher whose job is gone or no longer eligible.
        for (id, entry) in watchers where !keepIDs.contains(id) {
            entry.teardown()
            watchers.removeValue(forKey: id)
        }
    }

    // MARK: - Job control

    /// Run the job immediately. Idempotent — calling while already
    /// running is a no-op for the *current* run but now records a
    /// pending-rerun flag so the job re-fires the moment the
    /// in-flight run terminates. Without the
    /// rerun bit, watch-folder events that landed mid-run were lost
    /// and only a *future* event triggered another sync.
    func runNow(id: UUID) async {
        guard jobs[id] != nil else { return }
        if runners[id] != nil {
            pendingReruns.insert(id)
            return
        }
        // Checked after the runner slot: a run already in progress may
        // finish; only new runs need the entitlement.
        guard await isAuthorized() else {
            updateStatus(id: id, phase: .failed, message: String(
                localized: "sync.error.proRequired",
                defaultValue: "Running sync jobs requires Bucketeer Pro."
            ))
            return
        }
        // Re-read after the suspension: the job may have been edited,
        // deleted or started meanwhile.
        guard let job = jobs[id], runners[id] == nil else { return }
        updateStatus(id: id, phase: .planning, message: nil)
        let token = UUID()
        let task = Task { [weak self] in
            _ = await self?.execute(job: job, token: token)
        }
        runners[id] = Runner(token: token, task: task)
    }

    /// Cancel a running job. Idempotent. Cancels the orchestrating
    /// task **and** every transfer-manager task the engine has handed
    /// to the queue for this job.
    ///
    /// All bookkeeping happens before the first suspension; the awaits
    /// only cancel the transfers already detached from the run, so a
    /// `runNow` that slips in meanwhile starts a clean, cancellable run.
    func cancel(id: UUID) async {
        pendingReruns.remove(id)
        var transfersToCancel: Set<UUID> = []
        if let runner = runners.removeValue(forKey: id) {
            cancelledRuns.insert(runner.token)
            runner.task.cancel()
            transfersToCancel = activeTransferIDs.removeValue(forKey: runner.token) ?? []
        }
        if current[id] != nil {
            updateStatus(id: id, phase: .cancelled, message: nil)
        }
        for transferID in transfersToCancel {
            await transferManager.cancel(id: transferID)
        }
    }

    /// If the run was cancelled while the transfer was being enqueued,
    /// the new transfer would otherwise dangle. Catch it here and tear
    /// it down immediately.
    private func registerActiveTransfer(run token: UUID, transferID: UUID) {
        if cancelledRuns.contains(token) {
            Task { [transferManager] in await transferManager.cancel(id: transferID) }
            return
        }
        activeTransferIDs[token, default: []].insert(transferID)
    }

    private func unregisterActiveTransfer(run token: UUID, transferID: UUID) {
        activeTransferIDs[token]?.remove(transferID)
    }

    private func ownsSlot(jobID: UUID, run token: UUID) -> Bool {
        runners[jobID]?.token == token
    }

    // MARK: - Execution

    private func execute(job: SyncJob, token: UUID) async {
        let start = Date()
        // Release the runner slot, then
        // immediately re-trigger if a watch-folder event landed
        // while we were running. Without this, the rerun bit stays
        // set and is only acted on by the *next* fsevent, which
        // could be hours away.
        defer {
            // The task group has awaited every child by now, so no
            // transfer of this run can register any more.
            cancelledRuns.remove(token)
            activeTransferIDs.removeValue(forKey: token)
            if ownsSlot(jobID: job.id, run: token) {
                runners[job.id] = nil
                if pendingReruns.remove(job.id) != nil {
                    Task { [weak self] in await self?.runNow(id: job.id) }
                }
            }
        }

        let context: SyncRunContext
        do {
            context = try await resolveContext(for: job)
        } catch {
            updateStatus(
                id: job.id,
                run: token,
                phase: .failed,
                message: bucketeerError(error).errorDescription
            )
            return
        }
        // Pair the bookmark start with a guaranteed release at the end
        // of the run. Crucial for sandboxed local-folder endpoints —
        // forgetting to stop would leak the open access count and
        // could keep the volume mounted longer than necessary.
        defer {
            releaseSecurityScope(context.source)
            releaseSecurityScope(context.destination)
        }

        let sourceList: [S3Object]
        let destList: [S3Object]
        do {
            async let s = enumerate(endpoint: job.source, context: context.source)
            async let d = enumerate(endpoint: job.destination, context: context.destination)
            sourceList = try await s
            destList = try await d
        } catch {
            updateStatus(
                id: job.id,
                run: token,
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
            run: token,
            phase: .running,
            planned: planned,
            startedAt: start
        )

        var completed = 0
        var failed = 0
        /// Tracks which entries actually succeeded so move-mode does
        /// not delete the source for failed upserts.
        var successfulEntries: [SyncPlanner.PlanEntry] = []

        // Upserts: copy or transfer per entry.
        // honour `job.concurrency` instead of running serially. We
        // use a bounded task group with an inflight cap so the
        // configured parallelism is respected without exhausting
        // network resources.
        let parallelism = max(1, job.concurrency)
        do {
            try await withThrowingTaskGroup(
                of: (SyncPlanner.PlanEntry, Result<Void, Error>).self
            ) { group in
                var iterator = plan.upserts.makeIterator()
                var inflight = 0

                func enqueueNext() -> Bool {
                    guard let entry = iterator.next() else { return false }
                    group.addTask { [context, job] in
                        do {
                            try await self.execute(
                                upsert: entry,
                                job: job,
                                run: token,
                                context: context
                            )
                            return (entry, .success(()))
                        } catch {
                            return (entry, .failure(error))
                        }
                    }
                    inflight += 1
                    return true
                }

                for _ in 0..<parallelism {
                    if !enqueueNext() { break }
                }

                while inflight > 0 {
                    if Task.isCancelled {
                        group.cancelAll()
                        updateStatus(id: job.id, run: token, phase: .cancelled)
                        return
                    }
                    guard let result = try await group.next() else { break }
                    inflight -= 1
                    let (entry, outcome) = result
                    switch outcome {
                    case .success:
                        completed += 1
                        successfulEntries.append(entry)
                    case .failure:
                        failed += 1
                    }
                    updateStatus(
                        id: job.id,
                        run: token,
                        phase: .running,
                        planned: planned,
                        completed: completed,
                        failed: failed
                    )
                    _ = enqueueNext()
                }
            }
        } catch is CancellationError {
            updateStatus(id: job.id, run: token, phase: .cancelled)
            return
        } catch {
            // Per-entry failures are already counted via the Result
            // surface; this catch handles only group-level surprises.
        }
        // The `return` inside the task group only leaves the closure; a
        // cancelled run must not continue to deletes or overwrite its
        // `.cancelled` status with a terminal summary.
        guard !Task.isCancelled else {
            updateStatus(id: job.id, run: token, phase: .cancelled)
            return
        }

        // Mirror deletes (only when explicitly enabled).
        if job.mode == .mirror && job.deletePropagation {
            for key in plan.deletes {
                if Task.isCancelled { break }
                do {
                    try await deleteKey(key, from: job.destination, context: context.destination)
                    completed += 1
                } catch {
                    failed += 1
                }
                updateStatus(
                    id: job.id,
                    run: token,
                    phase: .running,
                    planned: planned,
                    completed: completed,
                    failed: failed
                )
            }
        }

        // Move mode: delete the source **only** for entries whose
        // upsert succeeded (failed copies must not
        // trigger source deletes), and only if the job was not
        // cancelled mid-flight. Count delete
        // failures so the final summary reflects them instead of
        // silently swallowing leftover-source duplicates.
        var moveDeleteFailures = 0
        if job.mode == .move && !Task.isCancelled {
            for entry in successfulEntries where !Task.isCancelled {
                do {
                    try await deleteKey(entry.sourceKey, from: job.source, context: context.source)
                } catch {
                    moveDeleteFailures += 1
                }
            }
            if moveDeleteFailures > 0 {
                failed += moveDeleteFailures
            }
        }

        let summary = moveDeleteFailures > 0
            ? "\(completed) ok / \(failed) failed (\(moveDeleteFailures) move-delete) / \(planned) planned"
            : "\(completed) ok / \(failed) failed / \(planned) planned"
        // Persist *before* publishing the
        // terminal status. Observers (`SyncJobDetailWindow` via
        // `SyncStatusBroker`) reload the job from the store on
        // terminal-phase transitions; if we updateStatus first
        // they race in ahead of `touchLastRun` and render a stale
        // snapshot. Swap the order so the store is up to date by
        // the time any observer reacts.
        guard ownsSlot(jobID: job.id, run: token) else { return }
        let lastRunAt = Date()
        try? await jobStore.touchLastRun(id: job.id, at: lastRunAt, summary: summary)
        if var refreshed = jobs[job.id] {
            refreshed.lastRunAt = lastRunAt
            refreshed.lastRunSummary = summary
            jobs[job.id] = refreshed
        }
        updateStatus(
            id: job.id,
            run: token,
            phase: failed > 0 ? .failed : .finished,
            planned: planned,
            completed: completed,
            failed: failed,
            message: summary
        )
    }

    // MARK: - Endpoint context

    /// Per-side runtime state for one run. S3 sides carry the resolved
    /// account; local sides carry the resolved root URL plus a flag
    /// indicating whether `startAccessingSecurityScopedResource` returned
    /// true, so `releaseSecurityScope()` knows whether to stop the scope
    /// at the end of the run.
    struct EndpointContext: Sendable {
        var account: S3Account?
        var localRoot: URL?
        var didStartSecurityScope: Bool
    }

    struct SyncRunContext: Sendable {
        let source: EndpointContext
        let destination: EndpointContext
    }

    /// Resolve both sides of the job into the runtime context the rest
    /// of the engine needs: S3 sides get an `S3Account`, local sides
    /// get a security-scoped URL with the scope already started.
    private func resolveContext(for job: SyncJob) async throws -> SyncRunContext {
        let accounts = try await accountStore.all()
        return SyncRunContext(
            source: try resolveEndpointContext(for: job.source, accounts: accounts),
            destination: try resolveEndpointContext(for: job.destination, accounts: accounts)
        )
    }

    private func resolveEndpointContext(
        for endpoint: SyncEndpoint,
        accounts: [S3Account]
    ) throws -> EndpointContext {
        switch endpoint {
        case .s3(let accountID, _, _):
            guard let account = accounts.first(where: { $0.id == accountID }) else {
                throw BucketeerError.unknown(message: "Sync account no longer exists.")
            }
            return EndpointContext(
                account: account,
                localRoot: nil,
                didStartSecurityScope: false
            )
        case .localFolder(let bookmark, let displayPath):
            let resolved = try LocalFolderEnumerator.resolveBookmark(bookmark)
            // A stale bookmark means macOS has
            // garbage-collected the underlying file identity. The
            // bookmark may still resolve to *a* URL but its security
            // scope is not the one the user originally granted.
            // Surface this as a job error so the user re-picks the
            // folder rather than silently syncing the wrong place.
            if resolved.isStale {
                throw BucketeerError.sandboxAccessDenied(resolved.url)
            }
            // A failed start means the sandbox
            // refused the scope. Continuing would either fail every
            // operation with confusing errors or, worse, succeed only
            // by accident if the URL happens to be inside our container.
            // Refuse upfront with a clear error so the user knows to
            // re-grant access.
            let didStart = resolved.url.startAccessingSecurityScopedResource()
            guard didStart else {
                throw BucketeerError.sandboxAccessDenied(URL(fileURLWithPath: displayPath))
            }
            return EndpointContext(
                account: nil,
                localRoot: resolved.url,
                didStartSecurityScope: true
            )
        }
    }

    private nonisolated func releaseSecurityScope(_ context: EndpointContext) {
        if context.didStartSecurityScope, let url = context.localRoot {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Enumeration

    /// Endpoint-aware listing. S3 / Azure sides recurse via the
    /// existing delimiter listing; local sides walk the filesystem.
    private func enumerate(
        endpoint: SyncEndpoint,
        context: EndpointContext
    ) async throws -> [S3Object] {
        switch endpoint {
        case .s3(_, let bucket, let prefix):
            guard let account = context.account else {
                throw BucketeerError.unknown(message: "Missing S3 account for endpoint.")
            }
            return try await listS3Recursively(account: account, bucket: bucket, prefix: prefix)
        case .localFolder:
            guard let root = context.localRoot else {
                throw BucketeerError.unknown(message: "Local folder root could not be resolved.")
            }
            return try LocalFolderEnumerator.enumerate(at: root)
        }
    }

    private func listS3Recursively(
        account: S3Account,
        bucket: String,
        prefix: String
    ) async throws -> [S3Object] {
        var output: [S3Object] = []
        var queue: [String] = [prefix]
        while !queue.isEmpty {
            let scope = queue.removeFirst()
            var token: String? = nil
            repeat {
                let page = try await browser.listObjects(
                    account: account,
                    bucket: bucket,
                    prefix: scope,
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

    // MARK: - Execute single entry

    /// Dispatch a single plan entry to the right transport. Four
    /// possible combinations: S3↔S3 (server-side copy or download
    /// + upload), S3→local (download to folder), local→S3 (upload
    /// from folder), local→local (filesystem copy).
    private func execute(
        upsert entry: SyncPlanner.PlanEntry,
        job: SyncJob,
        run token: UUID,
        context: SyncRunContext
    ) async throws {
        switch (job.source, job.destination) {
        case (.s3(_, let srcBucket, _), .s3(_, let dstBucket, _)):
            try await executeS3ToS3(
                entry: entry,
                run: token,
                sourceBucket: srcBucket,
                destinationBucket: dstBucket,
                sourceAccount: context.source.account,
                destinationAccount: context.destination.account
            )

        case (.s3(_, let srcBucket, _), .localFolder):
            guard let sourceAccount = context.source.account,
                  let destinationRoot = context.destination.localRoot
            else { throw BucketeerError.unknown(message: "Sync context incomplete.") }
            try await executeS3ToLocal(
                entry: entry,
                run: token,
                sourceAccount: sourceAccount,
                sourceBucket: srcBucket,
                destinationRoot: destinationRoot
            )

        case (.localFolder, .s3(_, let dstBucket, _)):
            guard let sourceRoot = context.source.localRoot,
                  let destinationAccount = context.destination.account
            else { throw BucketeerError.unknown(message: "Sync context incomplete.") }
            try await executeLocalToS3(
                entry: entry,
                run: token,
                sourceRoot: sourceRoot,
                destinationAccount: destinationAccount,
                destinationBucket: dstBucket
            )

        case (.localFolder, .localFolder):
            guard let sourceRoot = context.source.localRoot,
                  let destinationRoot = context.destination.localRoot
            else { throw BucketeerError.unknown(message: "Sync context incomplete.") }
            try await executeLocalToLocal(
                entry: entry,
                sourceRoot: sourceRoot,
                destinationRoot: destinationRoot
            )
        }
    }

    private func executeS3ToS3(
        entry: SyncPlanner.PlanEntry,
        run token: UUID,
        sourceBucket: String,
        destinationBucket: String,
        sourceAccount: S3Account?,
        destinationAccount: S3Account?
    ) async throws {
        guard let sourceAccount, let destinationAccount else {
            throw BucketeerError.unknown(message: "Sync context incomplete.")
        }
        let encryptionAllowsServerCopy = await encryptionGate?.allowsServerSideCopy(
            sourceAccountID: sourceAccount.id,
            sourceBucket: sourceBucket,
            destinationAccountID: destinationAccount.id,
            destinationBucket: destinationBucket
        ) ?? true
        if sourceAccount.id == destinationAccount.id, encryptionAllowsServerCopy {
            try await browser.copy(
                account: sourceAccount,
                fromBucket: sourceBucket,
                fromKey: entry.sourceKey,
                toBucket: destinationBucket,
                toKey: entry.destinationKey,
                metadata: nil
            )
            return
        }
        // Cross-account or encrypted side → temp staging, then upload.
        let staging = stagingURL(for: entry.sourceKey)
        let downloadID = await transferManager.enqueueDownload(
            account: sourceAccount,
            bucket: sourceBucket,
            key: entry.sourceKey,
            localURL: staging
        )
        registerActiveTransfer(run: token, transferID: downloadID)
        defer {
            unregisterActiveTransfer(run: token, transferID: downloadID)
            try? FileManager.default.removeItem(at: staging)
        }
        try terminalToError(await transferManager.awaitCompletion(id: downloadID))

        let uploadID = await transferManager.enqueueUpload(
            account: destinationAccount,
            bucket: destinationBucket,
            key: entry.destinationKey,
            localURL: staging,
            contentType: nil
        )
        registerActiveTransfer(run: token, transferID: uploadID)
        defer { unregisterActiveTransfer(run: token, transferID: uploadID) }
        try terminalToError(await transferManager.awaitCompletion(id: uploadID))
    }

    private func executeS3ToLocal(
        entry: SyncPlanner.PlanEntry,
        run token: UUID,
        sourceAccount: S3Account,
        sourceBucket: String,
        destinationRoot: URL
    ) async throws {
        // Download into a staging file, then move into place under the
        // destination folder root. The staging path is in the App's
        // sandbox temp dir (always writable, no security scope needed)
        // — the destination root is the user's chosen folder and is
        // covered by the run-level security-scoped resource start.
        let staging = stagingURL(for: entry.sourceKey)
        let downloadID = await transferManager.enqueueDownload(
            account: sourceAccount,
            bucket: sourceBucket,
            key: entry.sourceKey,
            localURL: staging
        )
        registerActiveTransfer(run: token, transferID: downloadID)
        defer { unregisterActiveTransfer(run: token, transferID: downloadID) }
        do {
            try terminalToError(await transferManager.awaitCompletion(id: downloadID))
            try LocalFolderWriter.install(
                from: staging,
                relativeKey: entry.destinationKey,
                under: destinationRoot
            )
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private func executeLocalToS3(
        entry: SyncPlanner.PlanEntry,
        run token: UUID,
        sourceRoot: URL,
        destinationAccount: S3Account,
        destinationBucket: String
    ) async throws {
        // Path-traversal guard: even on the local
        // *source* side, a malicious sync-job definition could carry
        // an entry.sourceKey of `../../../etc/passwd`. Refuse to
        // operate outside the chosen sync root.
        let sourceFile = try LocalFolderWriter.safeChildURL(
            root: sourceRoot,
            relativeKey: entry.sourceKey
        )
        guard FileManager.default.fileExists(atPath: sourceFile.path) else {
            throw BucketeerError.sandboxAccessDenied(sourceFile)
        }
        let uploadID = await transferManager.enqueueUpload(
            account: destinationAccount,
            bucket: destinationBucket,
            key: entry.destinationKey,
            localURL: sourceFile,
            contentType: nil
        )
        registerActiveTransfer(run: token, transferID: uploadID)
        defer { unregisterActiveTransfer(run: token, transferID: uploadID) }
        try terminalToError(await transferManager.awaitCompletion(id: uploadID))
    }

    private func executeLocalToLocal(
        entry: SyncPlanner.PlanEntry,
        sourceRoot: URL,
        destinationRoot: URL
    ) async throws {
        try Task.checkCancellation()
        let sourceFile = try LocalFolderWriter.safeChildURL(
            root: sourceRoot,
            relativeKey: entry.sourceKey
        )
        let destination = try LocalFolderWriter.safeChildURL(
            root: destinationRoot,
            relativeKey: entry.destinationKey
        )
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        // Atomic replace via temporary intermediate so a failed copy
        // never leaves a partial file at the destination.
        let staging = parent.appending(path: ".bucketeer-sync-staging-" + UUID().uuidString)
        do {
            try FileManager.default.copyItem(at: sourceFile, to: staging)
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(
                    destination,
                    withItemAt: staging,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try FileManager.default.moveItem(at: staging, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// Endpoint-aware delete used by mirror-delete and move-mode
    /// source removal. Routes to the right transport based on the
    /// endpoint kind. Local-folder deletes are idempotent (missing
    /// files succeed).
    private func deleteKey(
        _ key: String,
        from endpoint: SyncEndpoint,
        context: EndpointContext
    ) async throws {
        switch endpoint {
        case .s3(_, let bucket, _):
            guard let account = context.account else {
                throw BucketeerError.unknown(message: "Sync context incomplete.")
            }
            try await browser.delete(account: account, bucket: bucket, keys: [key])
        case .localFolder:
            guard let root = context.localRoot else {
                throw BucketeerError.unknown(message: "Local folder root unavailable.")
            }
            try LocalFolderWriter.delete(relativeKey: key, under: root)
        }
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

    // MARK: - Status

    /// With `run`, the update is dropped unless that run still owns the
    /// job's slot — a cancelled run must not overwrite its successor.
    private func updateStatus(
        id: UUID,
        run token: UUID? = nil,
        phase: SyncJobStatus.Phase,
        planned: Int? = nil,
        completed: Int? = nil,
        failed: Int? = nil,
        startedAt: Date? = nil,
        message: String? = nil
    ) {
        if let token, !ownsSlot(jobID: id, run: token) { return }
        var status = current[id] ?? SyncJobStatus(
            jobID: id,
            phase: phase,
            planned: 0,
            completed: 0,
            failed: 0,
            startedAt: nil,
            message: nil
        )
        let previousPhase = status.phase
        status.phase = phase
        if let planned { status.planned = planned }
        if let completed { status.completed = completed }
        if let failed { status.failed = failed }
        if let startedAt { status.startedAt = startedAt }
        status.message = message ?? status.message
        current[id] = status
        publish()
        // Phase 13.1 — audit-log key job transitions. Triggering only
        // when the phase actually changes avoids spamming the log on
        // progress updates that keep the same phase value.
        if previousPhase != phase {
            recordPhaseTransition(jobID: id, status: status)
        }
    }

    /// Translate the new phase into an activity-log row. Best-effort.
    private func recordPhaseTransition(jobID: UUID, status: SyncJobStatus) {
        guard let activityLog else { return }
        let job = jobs[jobID]
        let (kind, activityStatus): (ActivityKind, ActivityStatus)
        switch status.phase {
        case .planning, .awaitingConfirmation:
            kind = .syncRunStarted
            activityStatus = .info
        case .finished:
            kind = .syncRunFinished
            activityStatus = status.failed > 0 ? .failure : .success
        case .failed:
            kind = .syncRunFailed
            activityStatus = .failure
        case .cancelled:
            kind = .syncRunCancelled
            activityStatus = .cancelled
        case .running, .idle:
            return
        }
        let message: String?
        if status.planned > 0 || status.completed > 0 || status.failed > 0 {
            message = "planned: \(status.planned), completed: \(status.completed), failed: \(status.failed)"
        } else {
            message = status.message
        }
        let entry = ActivityEntry(
            kind: kind,
            status: activityStatus,
            message: message,
            syncJobID: jobID,
            syncJobName: job?.name
        )
        Task { [activityLog, entry] in
            await activityLog.record(entry)
        }
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
