//
//  SyncJobDetailWindow.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import SwiftUI
import BucketeerCore

/// Stand-alone window that lands behind `bucketeer://sync/<jobUUID>`
/// deep links. Phase 14 / v1.1-backlog-pull-forward. Renders the
/// job's identity + endpoints + current status + last-run summary
/// + a "Run Now" / "Cancel" / "Open in Sync list" action row.
///
/// Opened by `DeepLinkRouter` via the SwiftUI `openWindow`
/// environment action with the `"sync-job"` window id and the
/// job UUID encoded into the value binding.
struct SyncJobDetailWindow: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    /// Bound to the SwiftUI `WindowGroup`'s value parameter so a
    /// deep link can target a specific job without polluting the
    /// AppContainer with global navigation state.
    let jobID: UUID

    @State private var job: SyncJob?
    @State private var loadError: BucketeerError?

    var body: some View {
        // Codex R4 (high #2): read status through the multicast
        // broker so we don't race the sync list view model on the
        // single `SyncEngine.statuses` AsyncStream iterator.
        let status = container.syncStatusBroker.status(for: jobID)
        Group {
            if let job {
                detail(job: job, status: status)
            } else if let loadError {
                errorState(loadError)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .task { await loadJob() }
        // Codex R4 (medium): reload from the store on terminal
        // status transitions so lastRunAt / lastRunSummary update
        // when the in-flight run finishes. Without this the
        // snapshot loaded on open stays visible forever.
        .onChange(of: status.phase) { _, newPhase in
            switch newPhase {
            case .finished, .failed, .cancelled:
                Task { await loadJob() }
            default:
                break
            }
        }
        .navigationTitle(job?.name ?? "")
    }

    // MARK: - Subviews

    private func detail(job: SyncJob, status: SyncJobStatus) -> some View {
        VStack(spacing: 0) {
            Form {
                Section("syncDetail.section.identity") {
                    LabeledContent("syncDetail.field.name", value: job.name)
                    LabeledContent("syncDetail.field.mode") {
                        Text(job.mode.rawValue.capitalized)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("syncDetail.field.schedule") {
                        Text(job.schedule.rawValue)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("syncDetail.field.enabled") {
                        Text(job.enabled
                             ? String(localized: "common.yes", defaultValue: "Yes")
                             : String(localized: "common.no",  defaultValue: "No"))
                            .foregroundStyle(.secondary)
                    }
                }
                Section("syncDetail.section.endpoints") {
                    LabeledContent("syncDetail.field.source") {
                        Text(Self.label(for: job.source, accounts: container.accountListViewModel.accounts))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("syncDetail.field.destination") {
                        Text(Self.label(for: job.destination, accounts: container.accountListViewModel.accounts))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("syncDetail.section.runStatus") {
                    LabeledContent("syncDetail.field.phase") {
                        statusBadge(status.phase)
                    }
                    if let last = job.lastRunAt {
                        LabeledContent("syncDetail.field.lastRun") {
                            Text(last, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let summary = job.lastRunSummary, !summary.isEmpty {
                        LabeledContent("syncDetail.field.lastSummary") {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if status.planned > 0 {
                        ProgressView(
                            value: Double(status.completed),
                            total: Double(status.planned)
                        )
                        Text(
                            String(
                                format: NSLocalizedString("syncDetail.field.progress", comment: ""),
                                status.completed, status.failed, status.planned
                            )
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button {
                    Task { await container.syncEngine.runNow(id: job.id) }
                } label: {
                    Label("syncDetail.action.runNow", systemImage: "play.fill")
                }
                .disabled(status.phase == .running || !job.enabled)
                Button(role: .destructive) {
                    Task { await container.syncEngine.cancel(id: job.id) }
                } label: {
                    Label("syncDetail.action.cancel", systemImage: "stop.circle")
                }
                .disabled(status.phase != .running)
                Spacer()
                Button {
                    openWindow(id: "main")
                    dismissWindow()
                } label: {
                    Label("syncDetail.action.openInList", systemImage: "list.bullet")
                }
            }
            .padding(12)
        }
    }

    private func errorState(_ error: BucketeerError) -> some View {
        ContentUnavailableView {
            Label("syncDetail.error.title", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.errorDescription ?? "\(error)")
        }
    }

    // MARK: - Data

    @MainActor
    private func loadJob() async {
        do {
            let jobs = try await container.syncJobStore.all()
            if let match = jobs.first(where: { $0.id == jobID }) {
                self.job = match
                self.loadError = nil
            } else {
                self.loadError = .unknown(message: "No sync job with id \(jobID).")
            }
        } catch let error as BucketeerError {
            self.loadError = error
        } catch {
            self.loadError = .unknown(message: error.localizedDescription)
        }
    }

    // Status observation moved to SyncStatusBroker (Codex R4
    // high #2) — the window now reads via
    // `container.syncStatusBroker.status(for:)` in `body`, so
    // SwiftUI re-renders automatically when the broker's
    // @Observable snapshot changes. No per-window AsyncStream
    // iterator anymore.

    // MARK: - Helpers

    @ViewBuilder
    private func statusBadge(_ phase: SyncJobStatus.Phase) -> some View {
        let (label, colour): (LocalizedStringKey, Color) = {
            switch phase {
            case .idle:                 return ("sync.status.idle", .secondary)
            case .planning:             return ("sync.status.planning", .blue)
            case .awaitingConfirmation: return ("sync.status.awaiting", .yellow)
            case .running:              return ("sync.status.running", .blue)
            case .finished:             return ("sync.status.finished", .green)
            case .failed:               return ("sync.status.failed", .red)
            case .cancelled:            return ("sync.status.cancelled", .orange)
            }
        }()
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(colour.opacity(0.18)))
            .foregroundStyle(colour)
    }

    /// Friendly one-line endpoint label. Resolves account UUIDs
    /// against the loaded account list so the user sees names, not
    /// hex strings.
    static func label(for endpoint: SyncEndpoint, accounts: [S3Account]) -> String {
        switch endpoint {
        case .s3(let accountID, let bucket, let prefix):
            let name = accounts.first(where: { $0.id == accountID })?.name ?? "?"
            return prefix.isEmpty
                ? "\(name) · \(bucket)"
                : "\(name) · \(bucket)/\(prefix)"
        case .localFolder(_, let displayPath):
            return "📁 \(displayPath)"
        }
    }
}
