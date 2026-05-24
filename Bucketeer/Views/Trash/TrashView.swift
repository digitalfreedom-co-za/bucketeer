//
//  TrashView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import SwiftUI
import BucketeerCore

/// User-facing soft-delete bin. Lists every deleted-object record
/// with bucket / key / account / status / age columns and offers
/// **Restore**, **Forget**, and **Empty trash** actions. Phase 13.4.
struct TrashView: View {
    @Environment(AppContainer.self) private var container

    @State private var pendingEmpty: Bool = false
    @State private var pendingForget: TrashedItem?
    @State private var pendingRestore: TrashedItem?

    var body: some View {
        @Bindable var viewModel = container.trashViewModel
        VStack(spacing: 0) {
            if let actionError = viewModel.actionError {
                Label(actionError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            if viewModel.items.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                tableContent
            }
            Divider()
            footer
        }
        .toolbar { toolbarContent }
        .task { await viewModel.reload() }
        .confirmationDialog(
            "trash.empty.confirm.title",
            isPresented: $pendingEmpty,
            titleVisibility: .visible
        ) {
            Button("trash.empty.confirm.button", role: .destructive) {
                Task { await viewModel.empty() }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("trash.empty.confirm.message")
        }
        .confirmationDialog(
            "trash.forget.confirm.title",
            isPresented: Binding(
                get: { pendingForget != nil },
                set: { if !$0 { pendingForget = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingForget
        ) { item in
            Button("trash.forget.confirm.button", role: .destructive) {
                Task { await viewModel.forget(item) }
                pendingForget = nil
            }
            Button("common.cancel", role: .cancel) { pendingForget = nil }
        } message: { item in
            Text(item.displayName)
        }
        .confirmationDialog(
            "trash.restore.confirm.title",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRestore
        ) { item in
            Button("trash.restore.confirm.button") {
                Task { await viewModel.restore(item) }
                pendingRestore = nil
            }
            Button("common.cancel", role: .cancel) { pendingRestore = nil }
        } message: { item in
            Text(String(
                format: NSLocalizedString("trash.restore.confirm.message", comment: ""),
                item.bucket, item.key
            ))
        }
    }

    // MARK: - Subviews

    private var tableContent: some View {
        Table(container.trashViewModel.items) {
            TableColumn("trash.column.target") { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName).font(.callout.weight(.medium))
                    Text("\(item.bucket) · \(item.key)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            TableColumn("trash.column.account") { item in
                Text(item.accountName)
            }
            .width(min: 100, ideal: 140)
            TableColumn("trash.column.size") { item in
                if item.size > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .width(min: 80, ideal: 100)
            TableColumn("trash.column.status") { item in
                statusBadge(item.cacheStatus)
            }
            .width(min: 110, ideal: 140)
            TableColumn("trash.column.deleted") { item in
                Text(item.deletedAt, style: .relative)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help(Self.fullDate(item.deletedAt))
            }
            .width(min: 100, ideal: 130)
            TableColumn("trash.column.actions") { item in
                HStack(spacing: 8) {
                    Button {
                        pendingRestore = item
                    } label: {
                        Label("trash.action.restore", systemImage: "arrow.uturn.left.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(item.cacheStatus != .cached)
                    .help(item.cacheStatus == .cached
                          ? Text("trash.action.restore.help.available")
                          : Text("trash.action.restore.help.unavailable"))
                    Button {
                        pendingForget = item
                    } label: {
                        Label("trash.action.forget", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .width(min: 160, ideal: 180)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("trash.empty.title", systemImage: "trash.slash")
        } description: {
            Text("trash.empty.subtitle")
        }
    }

    private var footer: some View {
        let viewModel = container.trashViewModel
        return HStack {
            Text(
                String(
                    format: NSLocalizedString("trash.footer.count", comment: ""),
                    viewModel.items.count,
                    viewModel.totalCount
                )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            Spacer()
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await container.trashViewModel.reload() }
            } label: {
                Label("common.refresh", systemImage: "arrow.clockwise")
            }
        }
        ToolbarItem(placement: .destructiveAction) {
            Button(role: .destructive) {
                pendingEmpty = true
            } label: {
                Label("trash.action.empty", systemImage: "trash.slash")
            }
            .disabled(container.trashViewModel.items.isEmpty)
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: TrashCacheStatus) -> some View {
        let (label, colour): (LocalizedStringKey, Color) = {
            switch status {
            case .pending:          return ("trash.status.pending", .gray)
            case .cached:           return ("trash.status.cached", .green)
            case .skippedTooLarge:  return ("trash.status.tooLarge", .orange)
            case .skippedDisabled:  return ("trash.status.disabled", .gray)
            case .failed:           return ("trash.status.failed", .red)
            }
        }()
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(colour.opacity(0.18)))
            .foregroundStyle(colour)
    }

    private static func fullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f.string(from: date)
    }
}
