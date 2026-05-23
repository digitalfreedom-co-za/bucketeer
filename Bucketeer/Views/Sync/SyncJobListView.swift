//
//  SyncJobListView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import SwiftUI

struct SyncJobListView: View {
    @Bindable var viewModel: SyncJobListViewModel
    @State private var showingNewJobSheet: Bool = false
    @State private var editingJob: SyncJob?
    @State private var pendingDeletion: SyncJob?

    var body: some View {
        Group {
            if viewModel.jobs.isEmpty {
                emptyState
            } else {
                jobTable
            }
        }
        .navigationTitle("sync.title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewJobSheet = true
                } label: {
                    Label("sync.action.new", systemImage: "plus")
                }
                .disabled(viewModel.accounts.isEmpty)
            }
        }
        .sheet(isPresented: $showingNewJobSheet) {
            SyncJobSheet(
                mode: .create,
                accounts: viewModel.accounts,
                onSave: { job in
                    await viewModel.save(job)
                }
            )
        }
        .sheet(item: $editingJob) { job in
            SyncJobSheet(
                mode: .edit(job),
                accounts: viewModel.accounts,
                onSave: { updated in
                    await viewModel.save(updated)
                }
            )
        }
        .confirmationDialog(
            "sync.delete.confirm.title",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { job in
            Button("action.delete", role: .destructive) {
                Task { await viewModel.delete(id: job.id) }
                pendingDeletion = nil
            }
            Button("action.cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { job in
            Text("sync.delete.confirm.message \(job.name)")
        }
        .task { await viewModel.refresh() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("sync.empty.title", systemImage: "arrow.triangle.2.circlepath")
        } description: {
            Text("sync.empty.message")
        } actions: {
            Button("sync.action.new") {
                showingNewJobSheet = true
            }
            .disabled(viewModel.accounts.isEmpty)
        }
    }

    private var jobTable: some View {
        Table(viewModel.jobs) {
            TableColumn("sync.column.name") { job in
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.name)
                        .lineLimit(1)
                    Text(modeLabel(job.mode))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contextMenu { contextActions(for: job) }
            }
            TableColumn("sync.column.source") { job in
                Text(endpointLabel(job.source))
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            TableColumn("sync.column.destination") { job in
                Text(endpointLabel(job.destination))
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            TableColumn("sync.column.status") { job in
                statusLabel(for: job)
            }
            .width(min: 140, ideal: 180)
            TableColumn("sync.column.lastRun") { job in
                if let date = job.lastRunAt {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let summary = job.lastRunSummary {
                            Text(summary)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    Text("sync.lastRun.never")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 140, ideal: 160)
        }
    }

    @ViewBuilder
    private func contextActions(for job: SyncJob) -> some View {
        let status = viewModel.statuses[job.id]
        if status?.phase == .running {
            Button("sync.action.cancel", systemImage: "stop.circle") {
                Task { await viewModel.cancel(id: job.id) }
            }
        } else {
            Button("sync.action.runNow", systemImage: "play.fill") {
                Task { await viewModel.runNow(id: job.id) }
            }
        }
        Button("action.edit", systemImage: "pencil") {
            editingJob = job
        }
        Divider()
        Button("action.delete", systemImage: "trash", role: .destructive) {
            pendingDeletion = job
        }
    }

    @ViewBuilder
    private func statusLabel(for job: SyncJob) -> some View {
        if let status = viewModel.statuses[job.id] {
            switch status.phase {
            case .planning:
                Label("sync.status.planning", systemImage: "magnifyingglass")
                    .font(.caption)
            case .running:
                VStack(alignment: .leading, spacing: 2) {
                    Label("sync.status.running", systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                    if status.planned > 0 {
                        ProgressView(
                            value: Double(status.completed),
                            total: Double(status.planned)
                        )
                        .controlSize(.small)
                    }
                }
            case .finished:
                Label("sync.status.finished", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed:
                Label(status.message ?? String(localized: "sync.status.failed",
                                               defaultValue: "Failed"),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .cancelled:
                Label("sync.status.cancelled", systemImage: "stop.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .awaitingConfirmation:
                Label("sync.status.awaiting", systemImage: "exclamationmark.bubble")
                    .font(.caption)
            case .idle:
                Label("sync.status.idle", systemImage: "circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } else if !job.enabled {
            Label("sync.status.disabled", systemImage: "pause.circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            Label("sync.status.idle", systemImage: "circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func modeLabel(_ mode: SyncMode) -> LocalizedStringKey {
        switch mode {
        case .copy:   return "sync.mode.copy"
        case .move:   return "sync.mode.move"
        case .mirror: return "sync.mode.mirror"
        }
    }

    private func endpointLabel(_ endpoint: SyncEndpoint) -> String {
        let accountName = viewModel.accounts.first(where: { $0.id == endpoint.accountID })?.name
            ?? "?"
        return "\(accountName) · \(endpoint.bucket)/\(endpoint.prefix)"
    }
}
