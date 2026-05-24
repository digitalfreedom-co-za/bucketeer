//
//  ObjectListView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI
import BucketeerCore

struct ObjectListView: View {
    @Bindable var viewModel: BrowserViewModel
    @Environment(AppContainer.self) private var container

    @State private var showingNewFolderSheet: Bool = false
    @State private var renamingObject: S3Object?
    @State private var pendingDeletion: [S3Object] = []
    @State private var shareTarget: S3Object?

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
                    showingNewFolderSheet = true
                } label: {
                    Label("browser.action.newFolder", systemImage: "folder.badge.plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(viewModel.account == nil || viewModel.bucket == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await uploadFiles() }
                } label: {
                    Label("action.upload", systemImage: "arrow.up.circle")
                }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(viewModel.account == nil || viewModel.bucket == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    let keys = viewModel.selection
                    pendingDeletion = viewModel.objects.filter { keys.contains($0.key) }
                } label: {
                    Label("action.delete", systemImage: "trash")
                }
                .disabled(viewModel.selection.isEmpty)
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
            objectContextMenu(for: selection)
        }
        .sheet(isPresented: $showingNewFolderSheet) {
            NewFolderSheet { name in
                await viewModel.createFolder(named: name)
            }
        }
        .sheet(item: $renamingObject) { object in
            RenameSheet(original: object.displayName) { newName in
                await viewModel.rename(key: object.key, to: newName)
            }
        }
        .sheet(item: $shareTarget) { object in
            if let account = viewModel.account, let bucket = viewModel.bucket {
                PresignedURLSheet(
                    account: account,
                    bucket: bucket,
                    object: object,
                    generator: container.s3Browser
                )
            }
        }
        .confirmationDialog(
            confirmationTitle(),
            isPresented: Binding(
                get: { !pendingDeletion.isEmpty },
                set: { if !$0 { pendingDeletion = [] } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion.isEmpty ? nil : pendingDeletion
        ) { items in
            Button("action.delete", role: .destructive) {
                let keys = items.map(\.key)
                pendingDeletion = []
                Task { await viewModel.delete(keys: keys) }
            }
            Button("action.cancel", role: .cancel) {
                pendingDeletion = []
            }
        } message: { items in
            if items.count == 1 {
                Text("browser.action.delete.confirm.single \(items[0].displayName)")
            } else {
                Text("browser.action.delete.confirm.multi \(items.count)")
            }
        }
        .alert(
            "browser.action.errorTitle",
            isPresented: Binding(
                get: { viewModel.actionError != nil },
                set: { if !$0 { viewModel.actionError = nil } }
            ),
            presenting: viewModel.actionError
        ) { _ in
            Button("action.ok", role: .cancel) { viewModel.actionError = nil }
        } message: { error in
            Text(error.errorDescription ?? "")
        }
        .focusable()
        .onKeyPress(.space) {
            guard let object = resolvedSingleSelection(), !object.isFolder else {
                return .ignored
            }
            Task { await openQuickLook(for: object) }
            return .handled
        }
    }

    /// Resolve the table selection (Set<String>) into a single S3Object,
    /// or nil if zero or many are selected.
    private func resolvedSingleSelection() -> S3Object? {
        guard viewModel.selection.count == 1,
              let key = viewModel.selection.first
        else { return nil }
        return viewModel.objects.first(where: { $0.key == key })
    }

    /// Spacebar handler — surface the system Quick Look panel for the
    /// currently selected file. Triggers a cache fetch if needed; in the
    /// "requires explicit click" size band, the cache will still
    /// materialise on direct request.
    private func openQuickLook(for object: S3Object) async {
        guard let account = viewModel.account,
              let bucket = viewModel.bucket
        else { return }
        do {
            let url = try await container.previewCache.materialise(
                account: account,
                bucket: bucket,
                object: object
            )
            QuickLookPanelController.shared.show(url: url)
        } catch let error as BucketeerError {
            viewModel.actionError = error
        } catch {
            viewModel.actionError = .unknown(message: error.localizedDescription)
        }
    }

    // MARK: - Subviews

    private var table: some View {
        Table(viewModel.filteredObjects, selection: $viewModel.selection) {
            TableColumn("table.column.name") { object in
                HStack(spacing: 8) {
                    Image(systemName: object.isFolder ? "folder.fill" : iconName(for: object))
                        .foregroundStyle(object.isFolder ? Color.accentColor : .secondary)
                    Text(object.displayName)
                }
                .onTapGesture(count: 2) { handleOpen(object) }
                .draggable(objectRef(for: object))
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
        .dropDestination(for: URL.self) { urls, _ in
            handleURLDrop(urls)
        }
        .dropDestination(for: S3ObjectRef.self) { refs, _ in
            handleObjectRefDrop(refs)
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

    /// Build the drag payload for a row. Folders carry their key as well
    /// so the destination can build a folder-marker rename if needed.
    private func objectRef(for object: S3Object) -> S3ObjectRef {
        S3ObjectRef(
            accountID: viewModel.account?.id ?? UUID(),
            bucket: viewModel.bucket ?? "",
            key: object.key,
            displayName: object.displayName,
            size: object.size,
            etag: object.etag,
            isFolder: object.isFolder
        )
    }

    /// File-URL drop handler — uploads every dropped URL into the
    /// current prefix. Returns true so the system shows the drop
    /// accepted animation; the actual upload runs async.
    private func handleURLDrop(_ urls: [URL]) -> Bool {
        guard let account = viewModel.account,
              let bucket = viewModel.bucket
        else { return false }
        let prefix = viewModel.prefix
        Task {
            await container.dragDropCoordinator.uploadDroppedURLs(
                urls,
                account: account,
                bucket: bucket,
                prefix: prefix
            )
        }
        return true
    }

    /// Intra-app object drop — server-side copy (same account) or
    /// cross-account round-trip via the coordinator. Self-drops (drag a
    /// row back onto its own list) are filtered out in the coordinator.
    private func handleObjectRefDrop(_ refs: [S3ObjectRef]) -> Bool {
        guard let account = viewModel.account,
              let bucket = viewModel.bucket
        else { return false }
        let prefix = viewModel.prefix
        Task {
            for ref in refs {
                await container.dragDropCoordinator.dropObjectRef(
                    ref,
                    destinationAccount: account,
                    destinationBucket: bucket,
                    destinationPrefix: prefix
                )
            }
        }
        return true
    }

    @ViewBuilder
    private func objectContextMenu(for selection: Set<String>) -> some View {
        let resolved = viewModel.objects.filter { selection.contains($0.key) }
        if resolved.count == 1, let object = resolved.first {
            if !object.isFolder {
                Button("action.download", systemImage: "arrow.down.circle") {
                    Task { await downloadObject(object) }
                }
                Button("share.menu.getLink", systemImage: "link") {
                    shareTarget = object
                }
            }
            Button("action.rename", systemImage: "pencil") {
                renamingObject = object
            }
            Divider()
            Button("action.delete", systemImage: "trash", role: .destructive) {
                pendingDeletion = [object]
            }
        } else if !resolved.isEmpty {
            Button("action.delete.multi \(resolved.count)", systemImage: "trash", role: .destructive) {
                pendingDeletion = resolved
            }
        }
    }

    // MARK: - Actions

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

    private func handleOpen(_ object: S3Object) {
        if object.isFolder {
            Task { await viewModel.openFolder(object) }
        }
        // Files: preview/download wiring lands in Phase 6.
    }

    private func confirmationTitle() -> LocalizedStringKey {
        pendingDeletion.count == 1
            ? "browser.action.delete.title.single"
            : "browser.action.delete.title.multi"
    }

    // MARK: - Helpers

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

    private func errorPlaceholder(_ error: BucketeerError) -> some View {
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
