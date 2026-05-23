//
//  ObjectListView.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI

struct ObjectListView: View {
    @Bindable var viewModel: BrowserViewModel
    @Environment(AppContainer.self) private var container

    var body: some View {
        Group {
            if let error = viewModel.error, viewModel.objects.isEmpty {
                errorPlaceholder(error)
            } else if viewModel.isLoading && viewModel.objects.isEmpty {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredObjects.isEmpty {
                ContentUnavailableView.search
            } else {
                table
            }
        }
        .navigationTitle(viewModel.bucket ?? "")
        .navigationSubtitle(viewModel.prefix.isEmpty ? "" : viewModel.prefix)
        .searchable(text: $viewModel.searchText, prompt: Text("browser.search.placeholder"))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    Task { await viewModel.goUp() }
                } label: {
                    Label("action.up", systemImage: "arrow.up")
                }
                .disabled(!viewModel.canGoUp)
            }
            ToolbarItem(placement: .principal) {
                BreadcrumbBar(viewModel: viewModel)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await uploadFiles() }
                } label: {
                    Label("action.upload", systemImage: "arrow.up.circle")
                }
                .disabled(viewModel.account == nil || viewModel.bucket == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("action.refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .contextMenu(forSelectionType: String.self) { selection in
            if selection.count == 1,
               let key = selection.first,
               let object = viewModel.objects.first(where: { $0.key == key }),
               !object.isFolder {
                Button("action.download", systemImage: "arrow.down.circle") {
                    Task { await downloadObject(object) }
                }
            }
        }
    }

    private func uploadFiles() async {
        guard let account = viewModel.account, let bucket = viewModel.bucket else { return }
        let urls = await FilePickers.pickFiles(
            title: String(localized: "upload.picker.title",
                          defaultValue: "Choose files to upload"),
            allowsMultipleSelection: true
        )
        guard !urls.isEmpty else { return }
        await container.transferQueueViewModel.enqueueUploads(
            account: account,
            bucket: bucket,
            prefix: viewModel.prefix,
            fileURLs: urls
        )
    }

    private func downloadObject(_ object: S3Object) async {
        guard let account = viewModel.account, let bucket = viewModel.bucket else { return }
        guard let target = await FilePickers.pickSaveLocation(
            suggestedName: object.displayName
        ) else { return }
        await container.transferQueueViewModel.enqueueDownload(
            account: account,
            bucket: bucket,
            key: object.key,
            to: target
        )
    }

    private var table: some View {
        Table(viewModel.filteredObjects, selection: $viewModel.selection) {
            TableColumn("table.column.name") { object in
                HStack(spacing: 8) {
                    Image(systemName: object.isFolder ? "folder.fill" : iconName(for: object))
                        .foregroundStyle(object.isFolder ? Color.accentColor : .secondary)
                    Text(object.displayName)
                }
                .onTapGesture(count: 2) {
                    handleOpen(object)
                }
            }
            TableColumn("table.column.size") { object in
                if !object.isFolder {
                    Text(ByteCountFormatter.string(fromByteCount: object.size, countStyle: .file))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 100)
            TableColumn("table.column.modified") { object in
                if !object.isFolder {
                    Text(object.lastModified, style: .date)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 120, ideal: 150)
            TableColumn("table.column.storage") { object in
                Text(object.storageClass ?? "")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .width(min: 80, ideal: 100)
        }
        .onAppear {
            if viewModel.objects.isEmpty {
                Task { await viewModel.loadObjectsResetting() }
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.hasMore {
                Button("action.loadMore") {
                    Task { await viewModel.loadMore() }
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 8)
            }
        }
    }

    private func handleOpen(_ object: S3Object) {
        if object.isFolder {
            Task { await viewModel.openFolder(object) }
        }
        // Files: preview/download wiring lands in Phase 6.
    }

    private func iconName(for object: S3Object) -> String {
        let lower = object.displayName.lowercased()
        if lower.hasSuffix(".pdf") { return "doc.richtext" }
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".png")
            || lower.hasSuffix(".gif") || lower.hasSuffix(".heic") {
            return "photo"
        }
        if lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") { return "film" }
        if lower.hasSuffix(".mp3") || lower.hasSuffix(".wav") || lower.hasSuffix(".m4a") {
            return "music.note"
        }
        if lower.hasSuffix(".zip") || lower.hasSuffix(".tar") || lower.hasSuffix(".gz") {
            return "archivebox"
        }
        if lower.hasSuffix(".txt") || lower.hasSuffix(".md") || lower.hasSuffix(".log") {
            return "doc.text"
        }
        if lower.hasSuffix(".json") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml")
            || lower.hasSuffix(".xml") || lower.hasSuffix(".html") {
            return "curlybraces"
        }
        return "doc"
    }

    private func errorPlaceholder(_ error: S3BrowserError) -> some View {
        ContentUnavailableView {
            Label("browser.error.title", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.errorDescription ?? "")
        } actions: {
            Button("action.retry") {
                Task { await viewModel.refresh() }
            }
        }
    }
}
