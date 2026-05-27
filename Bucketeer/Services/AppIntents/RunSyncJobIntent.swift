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
///
/// Codex audit R2 (low) follow-up — Phase 14: picks from a typed
/// `SyncJobEntity` list keyed on stable `id`. Duplicate display
/// names no longer cause the wrong job to fire.
struct RunSyncJobIntent: AppIntent {
    static let title: LocalizedStringResource = "Run sync job"
    static let description = IntentDescription(
        "Triggers one of your saved sync jobs immediately."
    )

    @Parameter(title: "Sync job")
    var job: SyncJobEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Run sync job \(\.$job)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let container = try await AppIntentsBridge.shared.container()
        // Re-resolve through the store so a job that was deleted
        // between the picker showing and the intent firing surfaces
        // a clear error.
        let live = try await container.syncJobStore.all()
        guard let match = live.first(where: { $0.id == job.id }) else {
            throw BucketeerError.unknown(
                message: "Sync job is no longer configured."
            )
        }
        await container.syncEngine.runNow(id: match.id)
        return .result(value: match.name)
    }
}
