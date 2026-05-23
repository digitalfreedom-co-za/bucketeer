//
//  TransferManager.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation
@preconcurrency import SotoS3
@preconcurrency import NIOCore

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
    private var items: [UUID: QueuedItem] = [:]
    private var order: [UUID] = []
    private var workers: [UUID: Task<Void, Never>] = [:]
    /// IDs whose state has reached a terminal value. Once an ID is in
    /// here, `setState` ignores any further writes — so a late progress
    /// callback or a delayed completion cannot bring a cancelled task
    /// back to life.
    private var terminated: Set<UUID> = []

    init(factory: S3ClientFactory) {
        self.factory = factory
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
        if var item = items[id], !item.task.state.isTerminal {
            item.task.state = .cancelled
            items[id] = item
            terminated.insert(id)
            publish()
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
        }
        publish()
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

        let s3: S3
        do {
            s3 = try await factory.client(for: item.account)
        } catch {
            setState(id: id, state: .failed(message: errorMessage(error)))
            return
        }

        do {
            if item.fileSize >= Self.multipartThreshold {
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
                setState(
                    id: id,
                    state: .running(bytesTransferred: total, totalBytes: total)
                )
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
        }
        publish()
    }

    private func publish() {
        let snapshot = order.compactMap { items[$0]?.task }
        continuation.yield(snapshot)
    }

    private func errorMessage(_ error: Error) -> String {
        if let domainError = error as? S3BrowserError {
            return domainError.errorDescription ?? "\(error)"
        }
        return error.localizedDescription
    }
}
