//
//  SyncStatusBroker.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import Observation
import BucketeerCore

/// Single-subscriber → many-observer broadcast for SyncEngine
/// status updates. Codex audit R4 (high): `SyncEngine.statuses` is
/// an `AsyncStream`, which delivers each yielded value to exactly
/// one waiting iterator. Two consumers (the list view model + the
/// new sync-job detail window) racing on the same stream would
/// starve each other. The broker subscribes once at construction
/// and republishes via `@Observable`, so every SwiftUI view that
/// reads `statuses` gets the same snapshot.
@MainActor
@Observable
final class SyncStatusBroker {
    /// Latest snapshot of every job's status, keyed by job id for
    /// O(1) lookup from the detail window.
    private(set) var statuses: [UUID: SyncJobStatus] = [:]

    nonisolated(unsafe) private var pumpTask: Task<Void, Never>?

    init(syncEngine: SyncEngine) {
        let stream = syncEngine.statuses
        pumpTask = Task { [weak self] in
            for await snapshot in stream {
                guard let self else { return }
                var next: [UUID: SyncJobStatus] = [:]
                for status in snapshot {
                    next[status.jobID] = status
                }
                self.statuses = next
            }
        }
    }

    /// Convenience accessor — returns the current status for a job
    /// or the implicit `.idle` baseline when the engine hasn't
    /// published anything yet.
    func status(for jobID: UUID) -> SyncJobStatus {
        statuses[jobID]
            ?? SyncJobStatus(jobID: jobID, phase: .idle)
    }

    deinit {
        // Task uses weak self so a leaked pump self-terminates;
        // explicit cancel here is only relevant in tests.
        pumpTask?.cancel()
    }
}
