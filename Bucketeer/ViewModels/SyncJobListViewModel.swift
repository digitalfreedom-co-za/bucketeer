//
//  SyncJobListViewModel.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import BucketeerCore

@MainActor
@Observable
final class SyncJobListViewModel {
    var jobs: [SyncJob] = []
    var statuses: [UUID: SyncJobStatus] = [:]
    var accounts: [S3Account] = []
    var error: BucketeerError?

    private let jobStore: any SyncJobStoring
    private let engine: SyncEngine
    private let accountStore: any AccountStoring
    private var statusObserver: Task<Void, Never>?

    init(
        jobStore: any SyncJobStoring,
        engine: SyncEngine,
        accountStore: any AccountStoring
    ) {
        self.jobStore = jobStore
        self.engine = engine
        self.accountStore = accountStore
    }

    /// Initial load called once from the AppContainer construction
    /// site. Refreshes the in-memory model, primes the engine with the
    /// persisted job list, and subscribes to its status stream.
    func bootstrap() async {
        await refresh()
        do {
            try await engine.reload()
        } catch let err as BucketeerError {
            self.error = err
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
        startObservingStatuses()
    }

    func refresh() async {
        do {
            jobs = try await jobStore.all()
        } catch let err as BucketeerError {
            self.error = err
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
        do {
            accounts = try await accountStore.all()
        } catch {
            // Accounts may legitimately be empty at first launch — keep
            // the previous error if any rather than overwriting with a
            // less informative one.
        }
    }

    func save(_ job: SyncJob) async {
        do {
            try await jobStore.upsert(job)
            try await engine.reload()
            await refresh()
        } catch let err as BucketeerError {
            self.error = err
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
    }

    func delete(id: UUID) async {
        do {
            await engine.cancel(id: id)
            try await jobStore.delete(id: id)
            try await engine.reload()
            await refresh()
        } catch let err as BucketeerError {
            self.error = err
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
    }

    func runNow(id: UUID) async {
        await engine.runNow(id: id)
    }

    func cancel(id: UUID) async {
        await engine.cancel(id: id)
    }

    private func startObservingStatuses() {
        guard statusObserver == nil else { return }
        let stream = engine.statuses
        statusObserver = Task { [weak self] in
            for await snapshot in stream {
                var map: [UUID: SyncJobStatus] = [:]
                for status in snapshot { map[status.jobID] = status }
                self?.statuses = map
            }
        }
    }
}
