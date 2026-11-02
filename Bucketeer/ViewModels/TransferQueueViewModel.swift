//
//  TransferQueueViewModel.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation
import UniformTypeIdentifiers
import BucketeerCore

@MainActor
@Observable
final class TransferQueueViewModel {
    var tasks: [TransferTask] = []

    private let transferManager: any Transferring
    private var observerTask: Task<Void, Never>?

    init(transferManager: any Transferring) {
        self.transferManager = transferManager
    }

    func startObserving() {
        guard observerTask == nil else { return }
        let stream = transferManager.tasks
        observerTask = Task { [weak self] in
            for await snapshot in stream {
                self?.tasks = snapshot
            }
        }
    }

    func enqueueUploads(
        account: S3Account,
        bucket: String,
        prefix: String,
        fileURLs: [URL]
    ) async {
        for url in fileURLs {
            let key = prefix + url.lastPathComponent
            let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            _ = await transferManager.enqueueUpload(
                account: account,
                bucket: bucket,
                key: key,
                localURL: url,
                contentType: contentType
            )
        }
    }

    func enqueueDownload(
        account: S3Account,
        bucket: String,
        key: String,
        to localURL: URL
    ) async {
        _ = await transferManager.enqueueDownload(
            account: account,
            bucket: bucket,
            key: key,
            localURL: localURL
        )
    }

    func cancel(_ id: UUID) async {
        await transferManager.cancel(id: id)
    }

    func clearTerminal() async {
        await transferManager.clearTerminal()
    }

    var activeCount: Int {
        tasks.reduce(0) { acc, task in
            switch task.state {
            case .running, .queued: return acc + 1
            default: return acc
            }
        }
    }
}
