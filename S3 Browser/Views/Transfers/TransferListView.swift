//
//  TransferListView.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI

struct TransferListView: View {
    @Bindable var viewModel: TransferQueueViewModel

    var body: some View {
        Group {
            if viewModel.tasks.isEmpty {
                ContentUnavailableView(
                    "transfers.empty.title",
                    systemImage: "arrow.up.arrow.down.circle",
                    description: Text("transfers.empty.message")
                )
            } else {
                list
            }
        }
        .navigationTitle("sidebar.section.transfers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.clearTerminal() }
                } label: {
                    Label("transfers.action.clearFinished", systemImage: "trash")
                }
                .disabled(!viewModel.tasks.contains(where: { $0.state.isTerminal }))
            }
        }
    }

    private var list: some View {
        List {
            ForEach(viewModel.tasks) { task in
                TransferRow(task: task) {
                    Task { await viewModel.cancel(task.id) }
                }
            }
        }
        .listStyle(.inset)
    }
}

private struct TransferRow: View {
    let task: TransferTask
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: task.direction == .upload
                      ? "arrow.up.circle.fill"
                      : "arrow.down.circle.fill")
                    .foregroundStyle(task.direction == .upload ? Color.blue : Color.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.localURL.lastPathComponent)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(task.bucket)/\(task.key)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                trailingControls
            }
            progressLine
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var trailingControls: some View {
        switch task.state {
        case .running, .queued:
            Button(role: .destructive, action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "circle.slash")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var progressLine: some View {
        switch task.state {
        case .queued:
            ProgressView(value: 0)
                .progressViewStyle(.linear)
                .tint(.secondary)
        case .running(let bytes, let total):
            let fraction = total > 0 ? Double(bytes) / Double(total) : 0
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                Text(verbatim: "\(format(bytes)) / \(format(total))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .completed:
            Text("transfer.state.completed")
                .font(.caption2)
                .foregroundStyle(.green)
        case .failed(let message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(2)
        case .cancelled:
            Text("transfer.state.cancelled")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
