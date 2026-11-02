//
//  ObjectVersionsSheet.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import SwiftUI
import BucketeerCore

/// Lists every recorded version of an object and lets the user
/// **Restore** an older version (server-side copy on top of itself)
/// or **Delete** a specific version (or delete marker). Phase 13.6.
///
/// Providers that don't expose versions (Azure, plain MinIO, etc.)
/// surface a `featureNotSupported` banner instead of an empty list.
struct ObjectVersionsSheet: View {
    @State private var viewModel: ObjectVersionsViewModel
    @State private var pendingRestore: ObjectVersion?
    @State private var pendingDelete: ObjectVersion?
    @Environment(\.dismiss) private var dismiss

    init(viewModel: ObjectVersionsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let error = viewModel.error {
                    errorState(error)
                } else if viewModel.isLoading && viewModel.versions.isEmpty {
                    ProgressView().controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.versions.isEmpty {
                    ContentUnavailableView(
                        "versions.empty.title",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("versions.empty.message")
                    )
                } else {
                    versionTable
                }
            }
            .navigationTitle(Text(viewModel.key))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await viewModel.reload() }
                    } label: {
                        Label("common.refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .task { await viewModel.reload() }
            .confirmationDialog(
                "versions.restore.confirm.title",
                isPresented: Binding(
                    get: { pendingRestore != nil },
                    set: { if !$0 { pendingRestore = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingRestore
            ) { version in
                Button("versions.restore.confirm.button") {
                    if let v = pendingRestore {
                        Task { await viewModel.restore(v) }
                    }
                    pendingRestore = nil
                }
                Button("common.cancel", role: .cancel) { pendingRestore = nil }
            } message: { version in
                Text(String(
                    format: NSLocalizedString("versions.restore.confirm.message", comment: ""),
                    Self.dateFormatter.string(from: version.lastModified)
                ))
            }
            .confirmationDialog(
                "versions.delete.confirm.title",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { version in
                Button("versions.delete.confirm.button", role: .destructive) {
                    if let v = pendingDelete {
                        Task { await viewModel.deleteVersion(v) }
                    }
                    pendingDelete = nil
                }
                Button("common.cancel", role: .cancel) { pendingDelete = nil }
            } message: { version in
                Text(String(
                    format: NSLocalizedString("versions.delete.confirm.message", comment: ""),
                    Self.dateFormatter.string(from: version.lastModified)
                ))
            }
        }
        .frame(minWidth: 680, minHeight: 460)
    }

    private var versionTable: some View {
        Table(viewModel.versions) {
            TableColumn("versions.column.modified") { version in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.dateFormatter.string(from: version.lastModified))
                        .font(.callout)
                    if version.isLatest {
                        Text("versions.tag.latest")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                            .foregroundStyle(.tint)
                    }
                }
            }
            TableColumn("versions.column.size") { version in
                if version.isDeleteMarker {
                    Text("versions.tag.deleteMarker")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                } else {
                    Text(ByteCountFormatter.string(fromByteCount: version.size, countStyle: .file))
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 120)
            TableColumn("versions.column.versionId") { version in
                Text(version.versionId)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(version.versionId)
            }
            .width(min: 140, ideal: 200)
            TableColumn("versions.column.actions") { version in
                HStack(spacing: 8) {
                    Button {
                        pendingRestore = version
                    } label: {
                        Label("versions.action.restore", systemImage: "arrow.uturn.left.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(version.isLatest || version.isDeleteMarker
                              || viewModel.inFlightVersionId == version.versionId)
                    Button(role: .destructive) {
                        pendingDelete = version
                    } label: {
                        Label("versions.action.delete", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.inFlightVersionId == version.versionId)
                    if viewModel.inFlightVersionId == version.versionId {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .width(min: 200, ideal: 220)
        }
    }

    private func errorState(_ error: BucketeerError) -> some View {
        ContentUnavailableView {
            Label("versions.error.title", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.errorDescription ?? "\(error)")
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()
}
