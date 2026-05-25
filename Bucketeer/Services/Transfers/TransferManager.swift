//
//  TransferManager.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation
@preconcurrency import SotoS3
@preconcurrency import NIOCore
import BucketeerCore

/// Concurrent upload / download queue. Wraps Soto's multipart helpers
/// for large files; uses single-shot `putObject` / `getObject` for
/// anything below the multipart threshold (5 MB). Progress flows out
/// through an `AsyncStream<[TransferTask]>` that emits the full task
/// snapshot on every state change. Callers observe via the
/// `TransferQueueViewModel`.
actor TransferManager: Transferring {

    // MARK: - Configuration

    private static let multipartThreshold: Int64 = 5 * 1024 * 1024
    private static let multipartPartSize: Int = 8 * 1024 * 1024
    private let maxConcurrent: Int = 4

    // MARK: - Public stream

    nonisolated let tasks: AsyncStream<[TransferTask]>
    private let continuation: AsyncStream<[TransferTask]>.Continuation

    // MARK: - State

    private struct QueuedItem {
        let account: S3Account
        var task: TransferTask
        let contentType: String?
        let fileSize: Int64
    }

    private let factory: S3ClientFactory
    private let azure: AzureBlobTransporter?
    private let activityLog: (any ActivityLogging)?
    /// Optional resumable multipart driver. Phase 13.10. Bound at
    /// init time from `AppContainer` when the checkpoint store is
    /// available; absent in unit tests that don't need persistence.
    private let resumableUploader: S3ResumableUploader?
    /// Optional client-side-encryption gate. Phase 13.15. When
    /// present, upload bytes get wrapped in a `BucketeerEnvelope`
    /// before they hit the wire and download bytes get unwrapped
    /// after they arrive — but only for buckets the user has
    /// registered a key for.
    private let encryptionGate: BucketEncryptionGate?
    /// Optional bandwidth limiter. Phase 13.2. Charged accurately for
    /// the Azure block-blob path (transporter owns every wire chunk)
    /// and best-effort for Soto S3 — Soto's multipart helpers only
    /// surface fractional progress, so we charge per progress delta.
    private let limiter: BandwidthLimiter?
    /// Per-Soto-multipart cursor: how many bytes we've already charged
    /// the limiter for, keyed by transfer ID. Cleared on terminal
    /// transition.
    private var multipartBytesCharged: [UUID: Int64] = [:]
    private var items: [UUID: QueuedItem] = [:]
    private var order: [UUID] = []
    private var workers: [UUID: Task<Void, Never>] = [:]
    /// IDs whose state has reached a terminal value. Once an ID is in
    /// here, `setState` ignores any further writes — so a late progress
    /// callback or a delayed completion cannot bring a cancelled task
    /// back to life.
    private var terminated: Set<UUID> = []
    /// Per-ID waiters created by `awaitCompletion(id:)`. Each entry is
    /// a list of continuations resumed once the task reaches a terminal
    /// state. Codex review #2 — fixes the race where a fast transfer
    /// completed before a sync engine's stream-based waiter observed it.
    private var waiters: [UUID: [CheckedContinuation<TransferState, Never>]] = [:]
    /// Terminal-state cache for waiters that arrive after a transfer
    /// completed. Cleared when the task is removed via `clearTerminal`.
    private var terminalCache: [UUID: TransferState] = [:]

    init(
        factory: S3ClientFactory,
        azure: AzureBlobTransporter? = nil,
        activityLog: (any ActivityLogging)? = nil,
        limiter: BandwidthLimiter? = nil,
        resumableUploader: S3ResumableUploader? = nil,
        encryptionGate: BucketEncryptionGate? = nil
    ) {
        self.factory = factory
        self.azure = azure
        self.activityLog = activityLog
        self.limiter = limiter
        self.resumableUploader = resumableUploader
        self.encryptionGate = encryptionGate
        let (stream, continuation) = AsyncStream<[TransferTask]>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.tasks = stream
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
    }

    // MARK: - Transferring

    @discardableResult
    func enqueueUpload(
        account: S3Account,
        bucket: String,
        key: String,
        localURL: URL,
        contentType: String?
    ) async -> UUID {
        let id = UUID()
        let size = (try? localURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        let fileSize = Int64(size ?? 0)
        let task = TransferTask(
            id: id,
            direction: .upload,
            accountID: account.id,
            bucket: bucket,
            key: key,
            localURL: localURL,
            state: .queued,
            startedAt: Date()
        )
        items[id] = QueuedItem(
            account: account,
            task: task,
            contentType: contentType,
            fileSize: fileSize
        )
        order.append(id)
        publish()
        pump()
        return id
    }

    @discardableResult
    func enqueueDownload(
        account: S3Account,
        bucket: String,
        key: String,
        localURL: URL
    ) async -> UUID {
        let id = UUID()
        let task = TransferTask(
            id: id,
            direction: .download,
            accountID: account.id,
            bucket: bucket,
            key: key,
            localURL: localURL,
            state: .queued,
            startedAt: Date()
        )
        items[id] = QueuedItem(
            account: account,
            task: task,
            contentType: nil,
            fileSize: 0
        )
        order.append(id)
        publish()
        pump()
        return id
    }

    func cancel(id: UUID) async {
        workers[id]?.cancel()
        // Route through setState so `awaitCompletion(id:)` waiters get
        // resumed and `terminalCache` is populated — Codex blocker #2:
        // bypassing setState left sync engine + drag-drop round-trips
        // hung forever after a user-initiated cancel.
        if let item = items[id], !item.task.state.isTerminal {
            setState(id: id, state: .cancelled)
        }
    }

    /// Cancel all in-flight or queued transfers for an account. Called
    /// when an account is deleted so we don't leave workers running
    /// against a torn-down client.
    func cancelAll(for accountID: UUID) async {
        let ids = items.values
            .filter { $0.task.accountID == accountID && !$0.task.state.isTerminal }
            .map { $0.task.id }
        for id in ids {
            await cancel(id: id)
        }
    }

    /// Remove all completed / failed / cancelled tasks from the queue.
    func clearTerminal() {
        let removable = items.filter { _, value in value.task.state.isTerminal }.map(\.key)
        for id in removable {
            items.removeValue(forKey: id)
            order.removeAll { $0 == id }
            terminated.remove(id)
            terminalCache.removeValue(forKey: id)
        }
        publish()
    }

    /// Suspend until the supplied task reaches a terminal state and
    /// return that state. Safe for **late** subscribers: if the task
    /// already terminated before this call, the cached terminal state
    /// is returned immediately. Used by `SyncEngine` to wait on
    /// cross-account round-trip halves without racing the public
    /// `tasks` stream (Codex review #2).
    func awaitCompletion(id: UUID) async -> TransferState {
        if let cached = terminalCache[id] { return cached }
        if let item = items[id], item.task.state.isTerminal {
            terminalCache[id] = item.task.state
            return item.task.state
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<TransferState, Never>) in
            waiters[id, default: []].append(continuation)
        }
    }

    // MARK: - Scheduling

    private func pump() {
        while workers.count < maxConcurrent,
              let nextID = order.first(where: { id in
                  guard let item = items[id] else { return false }
                  if case .queued = item.task.state { return true }
                  return false
              }),
              let nextItem = items[nextID]
        {
            startWorker(for: nextItem)
        }
    }

    private func startWorker(for item: QueuedItem) {
        let id = item.task.id
        setState(id: id, state: .running(bytesTransferred: 0, totalBytes: item.fileSize))

        let task = Task { [weak self] in
            guard let self else { return }
            switch item.task.direction {
            case .upload:
                await self.performUpload(item: item)
            case .download:
                await self.performDownload(item: item)
            }
            await self.workerDidFinish(id: id)
        }
        workers[id] = task
    }

    private func workerDidFinish(id: UUID) {
        workers.removeValue(forKey: id)
        pump()
    }

    // MARK: - Upload

    private func performUpload(item: QueuedItem) async {
        let id = item.task.id
        let url = item.task.localURL
        let scopedAccessAcquired = url.startAccessingSecurityScopedResource()
        defer {
            if scopedAccessAcquired {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Phase 13.15 — if the destination bucket has a BYOK key
        // registered, seal the file into a sandboxed temp envelope
        // first and rewrite QueuedItem to point at it. The rest of
        // the upload pipeline (Soto helper / resumable / multipart /
        // single PUT) sees the encrypted file as if it were the
        // user-selected one.
        var item = item
        var encryptionCleanup: URL? = nil
        if let encryptionGate,
           let key = await encryptionGate.key(
               accountID: item.account.id,
               bucket: item.task.bucket
           ) {
            do {
                let plaintext = try Data(contentsOf: url, options: .mappedIfSafe)
                let envelope = try BucketeerEnvelope.seal(plaintext: plaintext, key: key)
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("bucketeer-enc-\(UUID().uuidString).bin")
                try envelope.write(to: temp, options: .atomic)
                item = QueuedItem(
                    account: item.account,
                    task: TransferTask(
                        id: item.task.id,
                        direction: item.task.direction,
                        accountID: item.task.accountID,
                        bucket: item.task.bucket,
                        key: item.task.key,
                        localURL: temp,
                        state: item.task.state,
                        startedAt: item.task.startedAt
                    ),
                    contentType: item.contentType,
                    fileSize: Int64(envelope.count)
                )
                encryptionCleanup = temp
            } catch {
                setState(id: id, state: .failed(message: errorMessage(error)))
                return
            }
        }
        defer {
            if let temp = encryptionCleanup {
                try? FileManager.default.removeItem(at: temp)
            }
        }

        if item.account.provider.family == .azureBlob {
            await performAzureUpload(item: item)
            return
        }

        let s3: S3
        do {
            s3 = try await factory.client(for: item.account)
        } catch {
            setState(id: id, state: .failed(message: errorMessage(error)))
            return
        }

        do {
            // Phase 13.10 — files large enough that an interruption
            // costs noticeable bandwidth go through the resumable
            // path (sequential parts + checkpoint after each).
            // Smaller multiparts keep Soto's parallel helper.
            if item.fileSize >= S3ResumableUploader.resumableThreshold,
               let resumableUploader {
                let total = item.fileSize
                try await resumableUploader.upload(
                    account: item.account,
                    bucket: item.task.bucket,
                    key: item.task.key,
                    localURL: item.task.localURL,
                    contentType: item.contentType,
                    fileSize: total,
                    progress: { @Sendable [weak self] bytes in
                        await self?.setState(
                            id: id,
                            state: .running(bytesTransferred: bytes, totalBytes: total)
                        )
                        await self?.chargeMultipartLimiter(id: id, observedBytes: bytes)
                    }
                )
            } else if item.fileSize >= Self.multipartThreshold {
                let total = item.fileSize
                _ = try await s3.multipartUpload(
                    .init(
                        bucket: item.task.bucket,
                        contentType: item.contentType,
                        key: item.task.key
                    ),
                    partSize: Self.multipartPartSize,
                    filename: item.task.localURL.path,
                    progress: { @Sendable [weak self] fraction in
                        let bytes = Int64(Double(total) * fraction)
                        await self?.setState(
                            id: id,
                            state: .running(bytesTransferred: bytes, totalBytes: total)
                        )
                        await self?.chargeMultipartLimiter(id: id, observedBytes: bytes)
                    }
                )
            } else {
                let data = try Data(contentsOf: item.task.localURL, options: .mappedIfSafe)
                let buffer = ByteBuffer(bytes: data)
                _ = try await s3.putObject(.init(
                    body: AWSHTTPBody(buffer: buffer),
                    bucket: item.task.bucket,
                    contentType: item.contentType,
                    key: item.task.key
                ))
                // Phase 13.2 — post-charge small PUTs as one chunk.
                await limiter?.consume(bytes: data.count)
                setState(
                    id: id,
                    state: .running(bytesTransferred: item.fileSize, totalBytes: item.fileSize)
                )
            }
            setState(id: id, state: .completed)
        } catch is CancellationError {
            setState(id: id, state: .cancelled)
        } catch {
            if Task.isCancelled {
                setState(id: id, state: .cancelled)
            } else {
                setState(id: id, state: .failed(message: errorMessage(error)))
            }
        }
    }

    // MARK: - Download

    private func performDownload(item: QueuedItem) async {
        let id = item.task.id
        let url = item.task.localURL
        let scopedAccessAcquired = url.startAccessingSecurityScopedResource()
        defer {
            if scopedAccessAcquired {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if item.account.provider.family == .azureBlob {
            await performAzureDownload(item: item)
            return
        }

        let s3: S3
        do {
            s3 = try await factory.client(for: item.account)
        } catch {
            setState(id: id, state: .failed(message: errorMessage(error)))
            return
        }

        // Pre-flight HEAD so we have a real total to report progress
        // against. multipartDownload internally does the same, but its
        // progress callback only gives us a fraction; we also use the
        // size to pick the right transfer path (zero / single-shot /
        // multipart).
        let total: Int64
        do {
            let head = try await s3.headObject(.init(
                bucket: item.task.bucket,
                key: item.task.key
            ))
            total = head.contentLength ?? 0
        } catch {
            setState(id: id, state: .failed(message: errorMessage(error)))
            return
        }
        setState(id: id, state: .running(bytesTransferred: 0, totalBytes: total))

        do {
            // Truncate any pre-existing file at the target so we never
            // leave trailing bytes from a previous version.
            try? FileManager.default.removeItem(at: item.task.localURL)

            if total == 0 {
                // Soto's multipartDownload refuses zero-length objects;
                // create the expected empty file ourselves.
                FileManager.default.createFile(
                    atPath: item.task.localURL.path,
                    contents: nil
                )
                setState(id: id, state: .completed)
                return
            }

            if total < Self.multipartThreshold {
                // Small objects: single-shot getObject — cheaper and
                // sidesteps the multipart path entirely.
                let response = try await s3.getObject(.init(
                    bucket: item.task.bucket,
                    key: item.task.key
                ))
                let buffer = try await response.body.collect(upTo: Int(total) + 1)
                let fileData = Data(buffer.readableBytesView)
                try fileData.write(to: item.task.localURL)
                // Phase 13.2 — post-charge small GETs as one chunk.
                await limiter?.consume(bytes: fileData.count)
                setState(
                    id: id,
                    state: .running(bytesTransferred: total, totalBytes: total)
                )
                await finalizeDownloadDecryption(item: item)
                setState(id: id, state: .completed)
                return
            }

            _ = try await s3.multipartDownload(
                .init(bucket: item.task.bucket, key: item.task.key),
                partSize: Self.multipartPartSize,
                filename: item.task.localURL.path,
                progress: { @Sendable [weak self] fraction in
                    let bytes = Int64(Double(total) * fraction)
                    await self?.setState(
                        id: id,
                        state: .running(bytesTransferred: bytes, totalBytes: total)
                    )
                    await self?.chargeMultipartLimiter(id: id, observedBytes: bytes)
                }
            )
            await finalizeDownloadDecryption(item: item)
            setState(id: id, state: .completed)
        } catch is CancellationError {
            setState(id: id, state: .cancelled)
        } catch {
            if Task.isCancelled {
                setState(id: id, state: .cancelled)
            } else {
                setState(id: id, state: .failed(message: errorMessage(error)))
            }
        }
    }

    // MARK: - Azure transports

    private func performAzureUpload(item: QueuedItem) async {
        let id = item.task.id
        guard let azure else {
            setState(
                id: id,
                state: .failed(message: "Azure transport not configured.")
            )
            return
        }
        let total = item.fileSize
        do {
            try await azure.upload(
                account: item.account,
                container: item.task.bucket,
                blob: item.task.key,
                localURL: item.task.localURL,
                contentType: item.contentType,
                progress: { @Sendable [weak self] bytes, totalBytes in
                    await self?.setState(
                        id: id,
                        state: .running(
                            bytesTransferred: bytes,
                            totalBytes: max(total, totalBytes)
                        )
                    )
                }
            )
            setState(id: id, state: .completed)
        } catch is CancellationError {
            setState(id: id, state: .cancelled)
        } catch {
            if Task.isCancelled {
                setState(id: id, state: .cancelled)
            } else {
                setState(id: id, state: .failed(message: errorMessage(error)))
            }
        }
    }

    private func performAzureDownload(item: QueuedItem) async {
        let id = item.task.id
        guard let azure else {
            setState(
                id: id,
                state: .failed(message: "Azure transport not configured.")
            )
            return
        }
        do {
            try await azure.download(
                account: item.account,
                container: item.task.bucket,
                blob: item.task.key,
                localURL: item.task.localURL,
                progress: { @Sendable [weak self] bytes, total in
                    await self?.setState(
                        id: id,
                        state: .running(bytesTransferred: bytes, totalBytes: total)
                    )
                }
            )
            await finalizeDownloadDecryption(item: item)
            setState(id: id, state: .completed)
        } catch is CancellationError {
            setState(id: id, state: .cancelled)
        } catch {
            if Task.isCancelled {
                setState(id: id, state: .cancelled)
            } else {
                setState(id: id, state: .failed(message: errorMessage(error)))
            }
        }
    }

    // MARK: - Encryption finalisation (Phase 13.15)

    /// Inspect the just-downloaded file. If it starts with the
    /// Bucketeer envelope magic AND we have a key for the
    /// (account, bucket) pair, decrypt in place. On a `failed`
    /// terminal state, this is a no-op — the caller's failure path
    /// stays untouched.
    ///
    /// Called from every download completion site so encryption is
    /// transparent regardless of single-shot vs multipart path.
    private func finalizeDownloadDecryption(item: QueuedItem) async {
        guard let encryptionGate else { return }
        let url = item.task.localURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
        guard BucketeerEnvelope.looksEncrypted(data) else { return }
        guard let key = await encryptionGate.key(
            accountID: item.account.id,
            bucket: item.task.bucket
        ) else { return }
        do {
            let plaintext = try BucketeerEnvelope.open(envelope: data, key: key)
            try plaintext.write(to: url, options: .atomic)
        } catch {
            // Leave the envelope on disk so the user can inspect /
            // re-attempt. The transfer's `completed` state remains —
            // the file simply isn't decrypted. Surfaced via the
            // activity log.
            await activityLog?.record(
                ActivityEntry(
                    kind: .download,
                    status: .failure,
                    accountID: item.account.id,
                    accountName: item.account.name,
                    bucket: item.task.bucket,
                    key: item.task.key,
                    errorMessage: "Decryption failed: \(error.localizedDescription)"
                )
            )
        }
    }

    // MARK: - Bandwidth (Phase 13.2)

    /// Soto's progress callback only gives us a fraction; this helper
    /// derives the delta since the last call and charges the limiter
    /// once. The cumulative observed-bytes value is monotonic per
    /// transfer, so we keep a per-ID cursor.
    private func chargeMultipartLimiter(id: UUID, observedBytes: Int64) async {
        guard let limiter else { return }
        let previous = multipartBytesCharged[id] ?? 0
        guard observedBytes > previous else { return }
        let delta = observedBytes - previous
        multipartBytesCharged[id] = observedBytes
        await limiter.consume(bytes: Int(delta))
    }

    // MARK: - State helpers

    private func setState(id: UUID, state: TransferState) {
        // Idempotent at the terminal boundary: once a task has reached a
        // terminal state (cancelled / completed / failed) we ignore any
        // further writes. Soto's progress callbacks and completion
        // returns can otherwise arrive after a user-initiated cancel.
        guard !terminated.contains(id), var item = items[id] else { return }
        item.task.state = state
        items[id] = item
        if state.isTerminal {
            terminated.insert(id)
            terminalCache[id] = state
            // Phase 13.2 — drop the bandwidth cursor; the transfer is
            // done and we don't want a future ID collision (UUIDs are
            // unique, but cleaning up is still tidy).
            multipartBytesCharged.removeValue(forKey: id)
            // Resume every waiter for this ID with the terminal state.
            // The waiter list is removed before resuming so a continuation
            // that immediately re-subscribes (unusual) does not loop.
            let pending = waiters.removeValue(forKey: id) ?? []
            for continuation in pending {
                continuation.resume(returning: state)
            }
            // Phase 13.1 — audit-log every terminal transition. Done
            // here (not at the call sites) so every code path that
            // reaches a terminal state is recorded exactly once.
            recordTerminal(item: item, state: state)
        }
        publish()
    }

    /// Push one row into the activity log on terminal transition.
    /// Best-effort — ActivityLogging.record never throws and we don't
    /// await it.
    private func recordTerminal(item: QueuedItem, state: TransferState) {
        guard let activityLog else { return }
        let kind: ActivityKind = item.task.direction == .upload ? .upload : .download
        let status: ActivityStatus
        var errorMessage: String? = nil
        switch state {
        case .completed:           status = .success
        case .cancelled:           status = .cancelled
        case .failed(let message):
            status = .failure
            errorMessage = message
        default:                   status = .info
        }
        let started = item.task.startedAt
        let duration = Int(Date().timeIntervalSince(started) * 1000)
        let entry = ActivityEntry(
            kind: kind,
            status: status,
            accountID: item.account.id,
            accountName: item.account.name,
            bucket: item.task.bucket,
            key: item.task.key,
            byteCount: item.fileSize > 0 ? item.fileSize : nil,
            durationMS: duration,
            errorMessage: errorMessage
        )
        Task { [activityLog, entry] in
            await activityLog.record(entry)
        }
    }

    private func publish() {
        let snapshot = order.compactMap { items[$0]?.task }
        continuation.yield(snapshot)
    }

    private func errorMessage(_ error: Error) -> String {
        if let domainError = error as? BucketeerError {
            return domainError.errorDescription ?? "\(error)"
        }
        return error.localizedDescription
    }
}
