//
//  BucketDashboardSheet.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import SwiftUI
import BucketeerCore

/// Aggregate dashboard for a single bucket — object count, total
/// size, top-10 largest, last activity, monthly cost estimate.
/// Phase 13.5.
///
/// Presented as a sheet from the browser toolbar when the user is
/// inside a bucket. Cancels its background walk on dismiss.
struct BucketDashboardSheet: View {
    @State private var viewModel: BucketDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: BucketDashboardViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    statsGrid
                    costEstimate
                    largestObjects
                    if viewModel.stats?.truncated == true {
                        truncationHint
                    }
                    if let error = viewModel.error {
                        errorBanner(error)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("dashboard.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.reload()
                    } label: {
                        Label("common.refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 540)
        .task {
            if viewModel.stats == nil { viewModel.reload() }
        }
        .onDisappear { viewModel.cancel() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: viewModel.account.provider.iconSystemName)
                .font(.title)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.bucket).font(.title2.bold())
                Text("\(viewModel.account.name) · \(viewModel.account.provider.displayName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.isLoading {
                ProgressView()
            }
        }
    }

    private var statsGrid: some View {
        let stats = viewModel.stats
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                statTile(
                    title: "dashboard.stat.objects",
                    value: stats.map { Self.numberFormatter.string(from: NSNumber(value: $0.objectCount)) ?? "—" } ?? "—",
                    icon: "doc.fill"
                )
                statTile(
                    title: "dashboard.stat.totalSize",
                    value: stats.map { ByteCountFormatter.string(fromByteCount: $0.totalBytes, countStyle: .file) } ?? "—",
                    icon: "internaldrive.fill"
                )
            }
            GridRow {
                statTile(
                    title: "dashboard.stat.folders",
                    value: stats.map { String($0.folderCount) } ?? "—",
                    icon: "folder.fill"
                )
                statTile(
                    title: "dashboard.stat.lastActivity",
                    value: stats?.lastModifiedAt.map { Self.dateFormatter.string(from: $0) } ?? "—",
                    icon: "clock.fill"
                )
            }
        }
    }

    private var costEstimate: some View {
        Group {
            if let usd = viewModel.monthlyCostUSD {
                GroupBox {
                    HStack(spacing: 12) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(
                                format: NSLocalizedString("dashboard.cost.monthly", comment: ""),
                                usd
                            ))
                            .font(.title3.weight(.medium))
                            Text("dashboard.cost.disclaimer")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var largestObjects: some View {
        Group {
            if let stats = viewModel.stats, !stats.largestObjects.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("dashboard.section.largest").font(.headline)
                        ForEach(stats.largestObjects) { entry in
                            HStack {
                                Text(entry.key)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var truncationHint: some View {
        let pageCount = viewModel.stats?.pagesWalked ?? 0
        return Label(
            String(
                format: NSLocalizedString("dashboard.truncated.hint", comment: ""),
                pageCount
            ),
            systemImage: "exclamationmark.bubble"
        )
        .font(.footnote)
        .foregroundStyle(.orange)
    }

    private func errorBanner(_ error: BucketeerError) -> some View {
        Label(error.errorDescription ?? "\(error)", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
    }

    private func statTile(title: LocalizedStringKey, value: String, icon: String) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.title3.weight(.semibold))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
