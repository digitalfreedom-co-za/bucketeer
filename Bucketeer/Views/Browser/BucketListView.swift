//
//  BucketListView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI

struct BucketListView: View {
    @Bindable var viewModel: BrowserViewModel

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.buckets.isEmpty {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error, viewModel.buckets.isEmpty {
                ContentUnavailableView {
                    Label("browser.error.title", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.errorDescription ?? "")
                } actions: {
                    Button("action.retry") {
                        Task { await viewModel.loadBuckets() }
                    }
                }
            } else if viewModel.buckets.isEmpty {
                ContentUnavailableView(
                    "browser.empty.buckets.title",
                    systemImage: "tray",
                    description: Text("browser.empty.buckets.message")
                )
            } else {
                bucketGrid
            }
        }
        .navigationTitle(viewModel.account?.name ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.loadBuckets() }
                } label: {
                    Label("action.refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
    }

    private var bucketGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: 16)],
                spacing: 16
            ) {
                ForEach(viewModel.buckets) { bucket in
                    bucketCard(bucket)
                        .onTapGesture(count: 2) {
                            Task { await viewModel.openBucket(bucket.name) }
                        }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func bucketCard(_ bucket: S3Bucket) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
                Spacer()
            }
            Text(bucket.name)
                .font(.headline)
                .lineLimit(2)
            if let created = bucket.createdAt {
                Text(created, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 0.5)
        )
        .contextMenu {
            Button("action.open", systemImage: "arrow.up.right.square") {
                Task { await viewModel.openBucket(bucket.name) }
            }
        }
    }
}
