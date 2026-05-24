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
    /// Codex #7: set on cancellation so a transfer that returned
    /// from `enqueue…` *after* the cancel call still gets caught and
    /// torn down. Without this guard the registration-race window
    /// could leak an in-flight transfer past the cancel.
    private var cancelledJobIDs: Set<UUID> = []
    /// Phase 9.10: per-job FSEvents watcher + the Task that pumps the
    /// watcher's debounced AsyncStream into runNow calls. Started on
    /// reload() for jobs with a local source and `.onLocalChange`
    /// schedule; torn down when the job is removed or its schedule
    /// changes to something non-watcher.
    private struct WatcherEntry {
        let watcher: LocalFolderWatcher
        let pumpTask: Task<Void, Never>
        let bookmarkSignature: Int  // hashValue of the bookmark data
    }
    private var watchers: [UUID: WatcherEntry] = [:]

    private let activityLog: (any ActivityLogging)?

    init(
        accountStore: any AccountStoring,
        jobStore: any SyncJobStoring,
        browser: any S3Browsing,
        transferManager: TransferManager,
        activityLog: (any ActivityLogging)? = nil
    ) {
        self.accountStore = accountStore
        self.jobStore = jobStore
        self.browser = browser
        self.transferManager = transferManager
        self.activityLog = activityLog
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
        // Reconcile FSEvents watchers for `.onLocalChange` jobs whose
        // source is a local folder. Phase 9.10.
        reconcileLocalChangeWatchers(against: all)
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
            let signature = bookmark.hashValue
            // Existing watcher with the same bookmark → leave running.
            if let existing = watchers[job.id], existing.bookmarkSignature == signature {
                continue
            }
            // Tear down stale watcher (bookmark moved or job edited)
            // before starting a fresh one.
            if let existing = watchers[job.id] {
                existing.pumpTask.cancel()
                existing.watcher.stop()
                watchers.removeValue(forKey: job.id)
            }
            guard let (url, _) = try? LocalFolderEnumerator.resolveBookmark(bookmark) else {
                continue
            }
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            let watcher = LocalFolderWatcher(rootURL: url, latencySeconds: 3.0)
            guard watcher.start() else { continue }
            // Pump the watcher's debounced events into runNow calls.
            // Each event triggers one sync — `runNow` is itself
            // idempotent (guards on `runners[id] == nil`) so an event
            // that lands mid-run is dropped harmlessly.
            let jobID = job.id
            let pump = Task { [weak self] in
                for await _ in watcher.events {
                    await self?.runNow(id: jobID)
                }
            }
            watchers[job.id] = WatcherEntry(
                watcher: watcher,
                pumpTask: pump,
                bookmarkSignature: signature
            )
        }
        // Stop every watcher whose job is gone or no longer eligible.
        for (id, entry) in watchers where !keepIDs.contains(id) {
            entry.pumpTask.cancel()
            entry.watcher.stop()
            watchers.removeValue(forKey: id)
        }
    }

    // MARK: - Job control

    /// Run the job immediately. Idempotent — calling while already
    /// running is a no-op (returns the existing runner).
    func runNow(id: UUID) async {
        guard let job = jobs[id], runners[id] == nil else { return }
        // Clear any previous cancellation flag so re-running a
        // cancelled job doesn't immediately tear new transfers down.
        cancelledJobIDs.remove(id)
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
        cancelledJobIDs.insert(id)
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

    /// Codex #7: if the job was cancelled while the transfer was
    /// being enqueued, the new transfer would otherwise dangle. Catch
    /// it here and tear it down immediately.
    private func registerActiveTransfer(jobID: UUID, transferID: UUID) {
        if cancelledJobIDs.contains(jobID) {
            Task { [transferManager] in await transferManager.cancel(id: transferID) }
            return
        }
        activeTransferIDs[jobID, default: []].insert(transferID)
    }

    private func unregisterActiveTransfer(jobID: UUID, transferID: UUID) {
        activeTransferIDs[jobID]?.remove(transferID)
    }

    // MARK: - Execution

    private func execute(job: SyncJob) async {
        let start = Date()
        defer { runners[job.id] = nil }

        let context: SyncRunContext
        do {
            context = try await resolveContext(for: job)
        } catch {
            updateStatus(
                id: job.id,
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

        // Upserts: copy or transfer per entry. Codex medium #11 —
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
                        updateStatus(id: job.id, phase: .cancelled)
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
                        phase: .running,
                        planned: planned,
                        completed: completed,
                        failed: failed
                    )
                    _ = enqueueNext()
                }
            }
        } catch is CancellationError {
            updateStatus(id: job.id, phase: .cancelled)
            return
        } catch {
            // Per-entry failures are already counted via the Result
            // surface; this catch handles only group-level surprises.
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
        // cancelled mid-flight. Codex medium #9 — count delete
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
            // Codex medium #5: a stale bookmark means macOS has
            // garbage-collected the underlying file identity. The
            // bookmark may still resolve to *a* URL but its security
            // scope is not the one the user originally granted.
            // Surface this as a job error so the user re-picks the
            // folder rather than silently syncing the wrong place.
            if resolved.isStale {
                throw BucketeerError.sandboxAccessDenied(resolved.url)
            }
            // Codex medium #6: a failed start means the sandbox
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
        context: SyncRunContext
    ) async throws {
        switch (job.source, job.destination) {
        case (.s3(_, let srcBucket, _), .s3(_, let dstBucket, _)):
            try await executeS3ToS3(
                entry: entry,
                job: job,
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
                job: job,
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
                job: job,
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
        job: SyncJob,
        sourceBucket: String,
        destinationBucket: String,
        sourceAccount: S3Account?,
        destinationAccount: S3Account?
    ) async throws {
        guard let sourceAccount, let destinationAccount else {
            throw BucketeerError.unknown(message: "Sync context incomplete.")
        }
        if sourceAccount.id == destinationAccount.id {
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
        // Cross-account → temp staging, then upload.
        let staging = stagingURL(for: entry.sourceKey)
        let downloadID = await transferManager.enqueueDownload(
            account: sourceAccount,
            bucket: sourceBucket,
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
            account: destinationAccount,
            bucket: destinationBucket,
            key: entry.destinationKey,
            localURL: staging,
            contentType: nil
        )
        registerActiveTransfer(jobID: job.id, transferID: uploadID)
        defer { unregisterActiveTransfer(jobID: job.id, transferID: uploadID) }
        try terminalToError(await transferManager.awaitCompletion(id: uploadID))
    }

    private func executeS3ToLocal(
        entry: SyncPlanner.PlanEntry,
        job: SyncJob,
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
        registerActiveTransfer(jobID: job.id, transferID: downloadID)
        defer { unregisterActiveTransfer(jobID: job.id, transferID: downloadID) }
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
        job: SyncJob,
        sourceRoot: URL,
        destinationAccount: S3Account,
        destinationBucket: String
    ) async throws {
        // Path-traversal guard (Codex blocker #1): even on the local
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
        registerActiveTransfer(jobID: job.id, transferID: uploadID)
        defer { unregisterActiveTransfer(jobID: job.id, transferID: uploadID) }
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
        // never leaves a partial file at the destination — Codex #8.
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
