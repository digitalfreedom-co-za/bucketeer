//
//  TransferManager.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation
import CryptoKit
@preconcurrency import SotoS3
@preconcurrency import NIOCore
import BucketeerCore

/// Concurrent upload / download queue. Wraps Soto's multipart helpers
/// for large files; uses single-shot `putObject` / `getObject` for
/// anything below the multipart threshold (5 MB). Progress flows out
/// through `taskUpdates()`, one stream of full task snapshots per
/// observer, and every terminal state through `completions()`.
actor TransferManager: Transferring {

    // MARK: - Configuration

    private static let multipartThreshold: Int64 = 5 * 1024 * 1024
    private static let multipartPartSize: Int = 8 * 1024 * 1024
    private let maxConcurrent: Int = 4

    // MARK: - Public streams

    /// Snapshots of the whole queue, one independent stream per observer
    /// (transfer list, menu bar, …).
    private let snapshots = Broadcast<[TransferTask]>(delivery: .snapshots)
    /// Every task once, when it reaches its terminal state — for work
    /// that must not miss a completion (auto-tagging).
    private let terminalEvents = Broadcast<TransferTask>(delivery: .events)

    nonisolated func taskUpdates() -> AsyncStream<[TransferTask]> {
        snapshots.subscribe()
    }

    nonisolated func completions() -> AsyncStream<TransferTask> {
        terminalEvents.subscribe()
    }

    // MARK: - State

    private struct QueuedItem {
        let account: S3Account
        var task: TransferTask
        let contentType: String?
        let fileSize: Int64
        /// Set on the trash-capture download so
        /// `finalizeDownloadDecryption` leaves the raw Bucketeer
        /// envelope on disk instead of decrypting it into plaintext.
        /// Without this, the local trash cache would hold plaintext
        /// outside the encryption boundary.
        var bypassDecryption: Bool = false
        /// Set on the trash restore of a cached envelope: the bytes are
        /// already sealed and must not be sealed a second time.
        var bypassEncryption: Bool = false
        /// Condition the server must check before it accepts the write
        /// (Open With round-trip). `nil` = unconditional.
        var precondition: WritePrecondition? = nil

        /// The same transfer against another local file (an encrypted
        /// envelope, a download staging file).
        func with(localURL: URL, fileSize: Int64? = nil) -> QueuedItem {
            QueuedItem(
                account: account,
                task: TransferTask(
                    id: task.id,
                    direction: task.direction,
                    accountID: task.accountID,
                    bucket: task.bucket,
                    key: task.key,
                    localURL: localURL,
                    state: task.state,
                    startedAt: task.startedAt
                ),
                contentType: contentType,
                fileSize: fileSize ?? self.fileSize,
                bypassDecryption: bypassDecryption,
                bypassEncryption: bypassEncryption,
                precondition: precondition
            )
        }
    }

    enum ConditionalUploadOutcome: Equatable, Sendable {
        /// `etag` is the one the write answered with (unquoted).
        case uploaded(etag: String?)
        case preconditionFailed
        case failed(message: String)
        case cancelled
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
    /// Terminal states a still-running worker reported; applied once
    /// the worker returns (`workerDidFinish`).
    private var pendingTerminal: [UUID: TransferState] = [:]
    /// Per-ID waiters created by `awaitCompletion(id:)`. Each entry is
    /// a list of continuations resumed once the task reaches a terminal
    /// state. Fixes the race where a fast transfer
    /// completed before a sync engine's stream-based waiter observed it.
    private var waiters: [UUID: [CheckedContinuation<TransferState, Never>]] = [:]
    /// Terminal-state cache for waiters that arrive after a transfer
    /// completed. Cleared when the task is removed via `clearTerminal`.
    private var terminalCache: [UUID: TransferState] = [:]
    /// Conditional uploads the server refused with 412. Read once by
    /// `uploadConditionally` and then dropped.
    private var preconditionRefused: Set<UUID> = []
    /// ETag each conditional upload's write answered with. Read once by
    /// `uploadConditionally` and then dropped.
    private var writtenETags: [UUID: String] = [:]

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
    }

    deinit {
        snapshots.finish()
        terminalEvents.finish()
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
        await enqueueUpload(
            account: account,
            bucket: bucket,
            key: key,
            localURL: localURL,
            contentType: contentType,
            bypassEncryption: false
        )
    }

    /// Variant for the trash restore, which re-uploads an object's raw
    /// bytes. Outside the protocol for the same reason as the
    /// `bypassDecryption` download variant.
    @discardableResult
    func enqueueUpload(
        account: S3Account,
        bucket: String,
        key: String,
        localURL: URL,
        contentType: String?,
        bypassEncryption: Bool,
        precondition: WritePrecondition? = nil
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
            fileSize: fileSize,
            bypassEncryption: bypassEncryption,
            precondition: precondition
        )
        order.append(id)
        publish()
        pump()
        return id
    }

    /// Uploads through the normal queue (so encryption applies and the
    /// transfer shows up in the list), but the server only accepts the
    /// write while `precondition` holds. Waits for the result.
    func uploadConditionally(
        account: S3Account,
        bucket: String,
        key: String,
        localURL: URL,
        contentType: String?,
        precondition: WritePrecondition
    ) async -> ConditionalUploadOutcome {
        let id = await enqueueUpload(
            account: account,
            bucket: bucket,
            key: key,
            localURL: localURL,
            contentType: contentType,
            bypassEncryption: false,
            precondition: precondition
        )
        let state = await awaitCompletion(id: id)
        let refused = preconditionRefused.remove(id) != nil
        let etag = writtenETags.removeValue(forKey: id)
        switch state {
        case .completed:
            return .uploaded(etag: etag)
        case .failed(let message):
            return refused ? .preconditionFailed : .failed(message: message)
        default:
            return .cancelled
        }
    }

    @discardableResult
    func enqueueDownload(
        account: S3Account,
        bucket: String,
        key: String,
        localURL: URL
    ) async -> UUID {
        await enqueueDownload(
            account: account,
            bucket: bucket,
            key: key,
            localURL: localURL,
            bypassDecryption: false
        )
    }

    /// Variant that lets internal callers (Phase 13.4 trash capture)
    /// opt out of `finalizeDownloadDecryption`. Outside the protocol
    /// because no UI / view-model needs the raw-envelope path —
    /// only the trash coordinator does, and it depends on the
    /// concrete `TransferManager` already.
    @discardableResult
    func enqueueDownload(
        account: S3Account,
        bucket: String,
        key: String,
        localURL: URL,
        bypassDecryption: Bool
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
            fileSize: 0,
            bypassDecryption: bypassDecryption
        )
        order.append(id)
        publish()
        pump()
        return id
    }

    /// Requests cancellation. A queued task without a worker ends right
    /// away; a running one ends — and resumes `awaitCompletion` waiters —
    /// only once its worker returned, because callers free the files
    /// and security scopes the worker may still be using.
    func cancel(id: UUID) async {
        if let worker = workers[id] {
            worker.cancel()
            return
        }
        // Route through setState so `awaitCompletion(id:)` waiters get
        // resumed and `terminalCache` is populated —
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
    /// `tasks` stream.
    func awaitCompletion(id: UUID) async -> TransferState {
        if let cached = terminalCache[id] { return cached }
        if let item = items[id], item.task.state.isTerminal {
            terminalCache[id] = item.task.state
            return item.task.state
        }
        // Unknown (or already cleared from the queue): nothing would
        // ever resume the waiter.
        guard items[id] != nil else { return .cancelled }
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

    /// The worker has returned: nothing touches the task's files any
    /// more, so its terminal state may now reach waiters and observers.
    private func workerDidFinish(id: UUID) {
        workers.removeValue(forKey: id)
        let outcome = pendingTerminal.removeValue(forKey: id) ?? .cancelled
        setState(id: id, state: outcome)
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
        let encryptionKey: SymmetricKey?
        do {
            encryptionKey = item.bypassEncryption ? nil : try await encryptionGate?.key(
                accountID: item.account.id,
                bucket: item.task.bucket
            )
        } catch {
            setState(id: id, state: .failed(message: errorMessage(error)))
            return
        }
        if let key = encryptionKey {
            do {
                let plaintext = try Data(contentsOf: url, options: .mappedIfSafe)
                let envelope = try BucketeerEnvelope.seal(plaintext: plaintext, key: key)
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("bucketeer-enc-\(UUID().uuidString).bin")
                try envelope.write(to: temp, options: .atomic)
                item = item.with(localURL: temp, fileSize: Int64(envelope.count))
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
            if let precondition = item.precondition {
                // Streams large files part by part; the precondition
                // guards the completion (Soto's helpers cannot carry it).
                let total = item.fileSize
                let etag = try await S3ConditionalUpload.upload(
                    fileAt: item.task.localURL,
                    bucket: item.task.bucket,
                    key: item.task.key,
                    contentType: item.contentType,
                    precondition: precondition,
                    writer: SotoObjectWriter(s3: s3),
                    progress: { @Sendable [weak self] bytes in
                        await self?.setState(id: id, state: .running(bytesTransferred: bytes, totalBytes: total))
                        await self?.chargeMultipartLimiter(id: id, observedBytes: bytes)
                    }
                )
                recordWrittenETag(etag, id: id)
            } else if item.fileSize >= S3ResumableUploader.resumableThreshold,
               let resumableUploader {
                // Phase 13.10 — files large enough that an interruption
                // costs noticeable bandwidth go through the resumable
                // path (sequential parts + checkpoint after each).
                // Smaller multiparts keep Soto's parallel helper.
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
        } catch let error where S3Service.isPreconditionFailure(error) {
            markPreconditionRefused(item: item)
        } catch {
            if Task.isCancelled {
                setState(id: id, state: .cancelled)
            } else {
                setState(id: id, state: .failed(message: errorMessage(error)))
            }
        }
    }

    private func recordWrittenETag(_ etag: String?, id: UUID) {
        guard let etag else { return }
        writtenETags[id] = ETag.normalized(etag)
    }

    private func markPreconditionRefused(item: QueuedItem) {
        preconditionRefused.insert(item.task.id)
        setState(
            id: item.task.id,
            state: .failed(message: errorMessage(BucketeerError.preconditionFailed(key: item.task.key)))
        )
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

        // The bytes land in a staging file; the destination is replaced
        // only once download and decryption succeeded, so every failure
        // leaves the existing file as it was.
        let staging = StagedDownload.stagingURL(for: url)
        let staged = item.with(localURL: staging)
        do {
            if item.account.provider.family == .azureBlob {
                try await downloadFromAzure(item: staged)
            } else {
                try await downloadFromS3(item: staged)
            }
            if let failure = await finalizeDownloadDecryption(item: staged) {
                StagedDownload.discard(staging)
                setState(id: id, state: .failed(message: failure))
                return
            }
            try StagedDownload.publish(staging, to: url)
            setState(id: id, state: .completed)
        } catch {
            StagedDownload.discard(staging)
            if error is CancellationError || Task.isCancelled {
                setState(id: id, state: .cancelled)
            } else {
                setState(id: id, state: .failed(message: errorMessage(error)))
            }
        }
    }

    private func downloadFromS3(item: QueuedItem) async throws {
        let id = item.task.id
        let s3 = try await factory.client(for: item.account)

        // Pre-flight HEAD so we have a real total to report progress
        // against. multipartDownload internally does the same, but its
        // progress callback only gives us a fraction; we also use the
        // size to pick the right transfer path (zero / single-shot /
        // multipart).
        let head = try await s3.headObject(.init(
            bucket: item.task.bucket,
            key: item.task.key
        ))
        let total = head.contentLength ?? 0
        setState(id: id, state: .running(bytesTransferred: 0, totalBytes: total))

        if total == 0 {
            // Soto's multipartDownload refuses zero-length objects;
            // create the expected empty file ourselves.
            try Data().write(to: item.task.localURL)
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
            let etag = try await azure.upload(
                account: item.account,
                container: item.task.bucket,
                blob: item.task.key,
                localURL: item.task.localURL,
                contentType: item.contentType,
                precondition: item.precondition,
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
            if item.precondition != nil {
                recordWrittenETag(etag, id: id)
            }
            setState(id: id, state: .completed)
        } catch is CancellationError {
            setState(id: id, state: .cancelled)
        } catch BucketeerError.preconditionFailed {
            markPreconditionRefused(item: item)
        } catch {
            if Task.isCancelled {
                setState(id: id, state: .cancelled)
            } else {
                setState(id: id, state: .failed(message: errorMessage(error)))
            }
        }
    }

    private func downloadFromAzure(item: QueuedItem) async throws {
        let id = item.task.id
        guard let azure else {
            throw BucketeerError.unknown(message: "Azure transport not configured.")
        }
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
    }

    // MARK: - Encryption finalisation (Phase 13.15)

    /// Inspect the just-downloaded staging file. If it starts with the
    /// Bucketeer envelope magic AND we have a key for the
    /// (account, bucket) pair, decrypt it in place before it is
    /// published to the destination.
    ///
    /// Called from every download completion site so encryption is
    /// transparent regardless of single-shot vs multipart path.
    ///
    /// Returns `nil` on success (including "nothing to decrypt") or
    /// the failure message when the file is an envelope we could not
    /// open. Callers translate that into a `.failed` transfer state —
    /// a green checkmark on a file that is still ciphertext would be
    /// a silent failure.
    private func finalizeDownloadDecryption(item: QueuedItem) async -> String? {
        // Trash-capture downloads pass
        // `bypassDecryption = true` so the local cache keeps the
        // raw envelope instead of holding plaintext copies of
        // encrypted objects.
        if item.bypassDecryption { return nil }
        guard let encryptionGate else { return nil }
        let url = item.task.localURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        guard BucketeerEnvelope.looksEncrypted(data) else { return nil }
        let lookedUpKey: SymmetricKey?
        do {
            lookedUpKey = try await encryptionGate.key(
                accountID: item.account.id,
                bucket: item.task.bucket
            )
        } catch {
            return errorMessage(error)
        }
        guard let key = lookedUpKey else {
            // Fail closed. The object is a Bucketeer
            // envelope but no key exists for this (account, bucket) —
            // e.g. the user deleted the key. A `.completed` transfer
            // would hand them ciphertext with a green checkmark.
            let message = String(
                localized: "error.encryptedNoKey",
                defaultValue: "The object is encrypted, but no key is configured for this bucket."
            )
            await activityLog?.record(
                ActivityEntry(
                    kind: .download,
                    status: .failure,
                    accountID: item.account.id,
                    accountName: item.account.name,
                    bucket: item.task.bucket,
                    key: item.task.key,
                    errorMessage: message
                )
            )
            return message
        }
        do {
            let plaintext = try BucketeerEnvelope.open(envelope: data, key: key)
            try plaintext.write(to: url, options: .atomic)
            return nil
        } catch {
            // Report the failure — the caller discards the staging
            // file and marks the transfer `.failed`, so neither
            // ciphertext nor a green checkmark reaches the destination.
            let message = "Decryption failed: \(error.localizedDescription)"
            await activityLog?.record(
                ActivityEntry(
                    kind: .download,
                    status: .failure,
                    accountID: item.account.id,
                    accountName: item.account.name,
                    bucket: item.task.bucket,
                    key: item.task.key,
                    errorMessage: message
                )
            )
            return message
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
        // A worker still running (it may be unwinding a cancel) holds its
        // result back until `workerDidFinish`; progress after a
        // cancellation request is dropped.
        if workers[id] != nil {
            if state.isTerminal {
                pendingTerminal[id] = pendingTerminal[id] ?? state
                return
            }
            if workers[id]?.isCancelled == true || pendingTerminal[id] != nil { return }
        }
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
            terminalEvents.publish(item.task)
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
        snapshots.publish(order.compactMap { items[$0]?.task })
    }

    private func errorMessage(_ error: Error) -> String {
        if let domainError = error as? BucketeerError {
            return domainError.errorDescription ?? "\(error)"
        }
        return error.localizedDescription
    }
}
