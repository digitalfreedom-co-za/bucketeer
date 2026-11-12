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
        /// Set on round-trip uploads into a bucket that had a key when
        /// the copy started: without a key at upload time the transfer
        /// fails instead of storing plaintext.
        var requiresEncryption: Bool = false
        var destinationHadKey: Bool = false
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
                    startedAt: task.startedAt,
                    isEncrypted: task.isEncrypted
                ),
                contentType: contentType,
                fileSize: fileSize ?? self.fileSize,
                bypassDecryption: bypassDecryption,
                bypassEncryption: bypassEncryption,
                requiresEncryption: requiresEncryption,
                destinationHadKey: destinationHadKey,
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
    /// Raw trash downloads retain their GET marker until the capture consumes it.
    private var downloadedMarkers: [UUID: Bool] = [:]

    func takeDownloadedMarker(id: UUID) -> Bool {
        downloadedMarkers.removeValue(forKey: id) ?? false
    }

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
    /// bytes, and for round trips that must not store plaintext
    /// (`requiresEncryption`). Outside the protocol for the same reason
    /// as the `bypassDecryption` download variant.
    @discardableResult
    func enqueueUpload(
        account: S3Account,
        bucket: String,
        key: String,
        localURL: URL,
        contentType: String?,
        bypassEncryption: Bool,
        requiresEncryption: Bool = false,
        destinationHadKey: Bool = false,
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
            requiresEncryption: requiresEncryption,
            destinationHadKey: destinationHadKey,
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
        // registered, seal the file segment by segment (#39) into a
        // private temp envelope first and rewrite QueuedItem to point at
        // it. The rest of the upload pipeline (single PUT / multipart)
        // sees the encrypted file as if it were the user-selected one.
        var item = item
        var encryptionCleanup: URL? = nil
        defer {
            if let encryptionCleanup {
                try? FileManager.default.removeItem(at: encryptionCleanup)
            }
        }
        let encryptionKey: SendableSymmetricKey?
        do {
            encryptionKey = item.bypassEncryption ? nil : try await encryptionGate?.uploadKey(
                accountID: item.account.id,
                bucket: item.task.bucket
            )
        } catch EncryptionError.backupNotConfirmed {
            setState(id: id, state: .failed(message: EncryptionError.backupNotConfirmed.localizedDescription))
            return
        } catch let error as EncryptionError where error == .keyRemoved {
            let message = item.destinationHadKey ? String(localized: "error.encryptionKeyRemoved") : errorMessage(error)
            setState(id: id, state: .failed(message: message))
            return
        } catch {
            setState(id: id, state: .failed(message: errorMessage(error)))
            return
        }
        if item.requiresEncryption, encryptionKey == nil, !item.bypassEncryption {
            let message = item.destinationHadKey
                ? String(localized: "error.encryptionKeyRemoved")
                : String(localized: "transfer.error.destinationNoKey")
            setState(id: id, state: .failed(message: message))
            return
        }
        let encrypted = encryptionKey != nil || item.bypassEncryption
        markEncrypted(id: id, encrypted)
        if let key = encryptionKey {
            do {
                let directory = try Self.makeEncryptionDirectory()
                encryptionCleanup = directory
                let envelope = directory.appendingPathComponent("payload.bckt", isDirectory: false)
                let size = try await Self.seal(url, to: envelope, key: key)
                item = item.with(localURL: envelope, fileSize: size)
            } catch {
                if error is CancellationError || Task.isCancelled {
                    setState(id: id, state: .cancelled)
                } else {
                    setState(id: id, state: .failed(message: errorMessage(error)))
                }
                return
            }
        }

        let metadata = encrypted ? [BucketeerEnvelope.s3MetadataKey: "1"] : nil

        if item.account.provider.family == .azureBlob {
            await performAzureUpload(item: item, encrypted: encrypted)
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
            // Freshly sealed envelopes skip the resumable path: a resume
            // needs the identical ciphertext, but every attempt seals
            // with a new random salt into a temp file that is deleted
            // afterwards, so its checkpoint could never match again and
            // would only strand parts on the server. The multipart path
            // below reads part by part and aborts on failure.
            if item.precondition == nil,
               encryptionKey == nil,
               item.fileSize >= S3ResumableUploader.resumableThreshold,
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
                    metadata: metadata,
                    fileSize: total,
                    progress: { @Sendable [weak self] bytes in
                        await self?.setState(
                            id: id,
                            state: .running(bytesTransferred: bytes, totalBytes: total)
                        )
                        await self?.chargeMultipartLimiter(id: id, observedBytes: bytes)
                    }
                )
            } else {
                // One PUT or buffered parts (never `aws-chunked`); a
                // precondition guards the write that makes it visible.
                let total = item.fileSize
                let etag = try await S3FileUpload.upload(
                    fileAt: item.task.localURL,
                    bucket: item.task.bucket,
                    key: item.task.key,
                    contentType: item.contentType,
                    precondition: item.precondition,
                    enforced: item.account.provider.conditionalRequests,
                    writer: SotoObjectWriter(s3: s3, metadata: metadata),
                    progress: { @Sendable [weak self] bytes in
                        await self?.setState(id: id, state: .running(bytesTransferred: bytes, totalBytes: total))
                        await self?.chargeMultipartLimiter(id: id, observedBytes: bytes)
                    }
                )
                // Only conditional writers collect the ETag.
                if item.precondition != nil { recordWrittenETag(etag, id: id) }
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
            let marked: Bool
            if item.account.provider.family == .azureBlob {
                marked = try await downloadFromAzure(item: staged)
            } else {
                marked = try await downloadFromS3(item: staged)
            }
            if let failure = await finalizeDownloadDecryption(item: staged, marked: marked) {
                StagedDownload.discard(staging)
                // Decryption checks for cancellation once per segment.
                setState(id: id, state: Task.isCancelled ? .cancelled : .failed(message: failure))
                return
            }
            // A cancel during decryption must not replace the file.
            try Task.checkCancellation()
            try StagedDownload.publish(staging, to: url)
            if item.bypassDecryption { downloadedMarkers[id] = marked }
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

    private func downloadFromS3(item: QueuedItem) async throws -> Bool {
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
            return BucketeerEnvelope.isMarked(head.metadata)
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
            return BucketeerEnvelope.isMarked(response.metadata)
        }

        _ = try await s3.multipartDownload(
            .init(bucket: item.task.bucket, ifMatch: item.account.provider.conditionalRequests.contains(.readIfMatch) ? head.eTag : nil, key: item.task.key),
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
        return BucketeerEnvelope.isMarked(head.metadata)
    }

    // MARK: - Azure transports

    private func performAzureUpload(item: QueuedItem, encrypted: Bool) async {
        let id = item.task.id
        guard let azure else {
            setState(
                id: id,
                state: .failed(message: String(localized: "transfer.error.azureUnavailable"))
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
                encrypted: encrypted,
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

    private func downloadFromAzure(item: QueuedItem) async throws -> Bool {
        let id = item.task.id
        guard let azure else {
            throw BucketeerError.unknown(message: String(localized: "transfer.error.azureUnavailable"))
        }
        return try await azure.download(
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

    /// Read and authenticate before publishing. Trash capture retains raw bytes
    /// and persists the response marker alongside its cached payload.
    private func finalizeDownloadDecryption(item: QueuedItem, marked: Bool) async -> String? {
        do {
            if item.bypassDecryption {
                // Only prove the staged file is readable; trash payloads can
                // reach gigabytes and must not be loaded into memory.
                try FileHandle(forReadingFrom: item.task.localURL).close()
                return nil
            }
            let key = try await encryptionGate?.sendableKey(
                accountID: item.account.id, bucket: item.task.bucket
            )
            try await Self.decrypt(item.task.localURL, marked: marked, key: key)
            return nil
        } catch {
            return encryptionErrorMessage(error)
        }
    }

    /// Marked bytes can be restored unchanged without a key. Unmarked legacy
    /// envelopes must authenticate before bypassing upload encryption.
    func cachedPayloadIsEncrypted(at url: URL, marked: Bool, accountID: UUID, bucket: String) async throws -> Bool {
        if marked { return true }
        // Without a key the upload never encrypts, so the restore is byte-exact.
        guard let key = try await encryptionGate?.sendableKey(accountID: accountID, bucket: bucket) else {
            return false
        }
        return try await Self.isEncrypted(url, marked: marked, key: key)
    }

    // Envelope work runs off the actor: sealing or decrypting gigabytes
    // must not stall the progress updates of the other transfers.

    /// A fresh owner-only folder for one upload's envelope, removed with
    /// the upload whatever its outcome.
    private static func makeEncryptionDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BucketeerEncryptedUploads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return directory
    }

    /// Seals `source` into `envelope` and returns the envelope's size.
    private static func seal(_ source: URL, to envelope: URL, key: SendableSymmetricKey) async throws -> Int64 {
        try await offActor {
            try BucketeerEnvelope.sealFile(at: source, to: envelope, key: key.key)
            let size = try FileManager.default.attributesOfItem(atPath: envelope.path)[.size] as? NSNumber
            return size?.int64Value ?? 0
        }
    }

    private static func decrypt(_ url: URL, marked: Bool, key: SendableSymmetricKey?) async throws {
        try await offActor {
            try BucketeerEnvelope.finalizeDownload(at: url, marked: marked, key: key?.key)
        }
    }

    private static func isEncrypted(_ url: URL, marked: Bool, key: SendableSymmetricKey) async throws -> Bool {
        try await offActor {
            try BucketeerEnvelope.payloadIsEncrypted(at: url, marked: marked, key: key.key)
        }
    }

    /// Runs synchronous work on the global executor and forwards
    /// cancellation, which the envelope codec checks once per segment.
    private static func offActor<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: .utility) { try work() }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func encryptionErrorMessage(_ error: Error) -> String {
        if error as? EncryptionError == .noKeyForBucket {
            return String(localized: "error.encryptedNoKey",
                          defaultValue: "The object is encrypted, but no key is configured for this bucket.")
        }
        return errorMessage(error)
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

    /// Marks the upload as sealed once it has resolved the bucket's key
    /// (or carries already-encrypted bytes). Queued tasks stay unmarked:
    /// the key may change before a worker picks them up.
    private func markEncrypted(id: UUID, _ isEncrypted: Bool) {
        guard !terminated.contains(id), items[id]?.task.isEncrypted != isEncrypted else { return }
        items[id]?.task.isEncrypted = isEncrypted
        publish()
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
