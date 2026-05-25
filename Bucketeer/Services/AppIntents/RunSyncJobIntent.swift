//
//  RunSyncJobIntent.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import AppIntents
import BucketeerCore

/// "Run a Bucketeer sync job now." Phase 13.12. Triggers the engine
/// the same way the UI's Run-Now button does and returns the job's
/// name so Shortcuts can confirm.
struct RunSyncJobIntent: AppIntent {
    static let title: LocalizedStringResource = "Run sync job"
    static let description = IntentDescription(
        "Triggers one of your saved sync jobs immediately."
    )

    @Parameter(title: "Job name", description: "Name of the sync job exactly as it appears in Bucketeer.")
    var jobName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Run sync job \(\.$jobName)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let container = try await AppIntentsBridge.shared.container()
        let jobs = try await container.syncJobStore.all()
        // Codex audit R2 (low): name is not a unique key. Pick the
        // first match but refuse to run when the name resolves to
        // more than one job, so a duplicate doesn't silently kick
        // off the wrong sync. A future phase will expose a stable
        // `SyncJobEntity` for the parameter picker.
        let matches = jobs.filter { $0.name == jobName }
        guard let match = matches.first else {
            throw BucketeerError.unknown(
                message: "No sync job named “\(jobName)” is configured."
            )
        }
        if matches.count > 1 {
            throw BucketeerError.unknown(
                message: "Multiple sync jobs are named “\(jobName)”. Rename one before triggering from Shortcuts."
            )
        }
        await container.syncEngine.runNow(id: match.id)
        return .result(value: match.name)
    }
}
