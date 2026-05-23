//
//  ObjectDetailView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI
import BucketeerCore

struct ObjectDetailView: View {
    @Bindable var viewModel: BrowserViewModel
    @Environment(AppContainer.self) private var container

    var selectedObject: S3Object? {
        guard let key = viewModel.selection.first,
              viewModel.selection.count == 1
        else { return nil }
        return viewModel.objects.first(where: { $0.key == key })
    }

    var body: some View {
        Group {
            if viewModel.selection.count > 1 {
                multiSelectionSummary
            } else if let object = selectedObject, !object.isFolder {
                splitForFile(object)
            } else if let object = selectedObject {
                metadata(for: object)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("detail.empty.message")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var multiSelectionSummary: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("detail.multi.count \(viewModel.selection.count)")
                .font(.headline)
            let total = viewModel.objects
                .filter { viewModel.selection.contains($0.key) }
                .reduce(Int64(0)) { $0 + $1.size }
            Text(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private func splitForFile(_ object: S3Object) -> some View {
        VSplitView {
            PreviewArea(object: object, viewModel: viewModel)
                .frame(minHeight: 220, idealHeight: 360)
                .environment(container)
            metadata(for: object)
                .frame(minHeight: 200)
        }
    }

    @ViewBuilder
    private func metadata(for object: S3Object) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(object)
                Divider()
                LabeledContent("detail.field.key") {
                    Text(object.key)
                        .textSelection(.enabled)
                        .monospaced()
                        .font(.callout)
                }
                LabeledContent("detail.field.size") {
                    Text(ByteCountFormatter.string(
                        fromByteCount: object.size,
                        countStyle: .file
                    ))
                    .monospacedDigit()
                }
                LabeledContent("detail.field.modified") {
                    Text(object.lastModified, style: .date)
                    Text(object.lastModified, style: .time)
                        .foregroundStyle(.secondary)
                }
                if let type = object.contentType, !type.isEmpty {
                    LabeledContent("detail.field.contentType") {
                        Text(type).textSelection(.enabled)
                    }
                }
                if let storageClass = object.storageClass, !storageClass.isEmpty {
                    LabeledContent("detail.field.storage") {
                        Text(storageClass).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !object.etag.isEmpty {
                    LabeledContent("detail.field.etag") {
                        Text(object.etag)
                            .font(.caption)
                            .monospaced()
                            .textSelection(.enabled)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(_ object: S3Object) -> some View {
        HStack(spacing: 12) {
            Image(systemName: object.isFolder ? "folder.fill" : "doc.fill")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(object.displayName)
                    .font(.title3)
                    .bold()
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(object.isFolder
                     ? String(localized: "detail.kind.folder",
                              defaultValue: "Folder")
                     : (object.contentType ?? "—"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Preview area

/// Loads and renders the live preview for a single selected object. Auto
/// fetches when the object is small enough; offers an explicit button
/// otherwise. Handles loading / error states inline so the parent stays
/// declarative.
private struct PreviewArea: View {
    let object: S3Object
    let viewModel: BrowserViewModel
    @Environment(AppContainer.self) private var container

    enum State: Equatable {
        case idle
        case requiresClick(sizeBytes: Int64)
        case loading
        case ready(URL)
        case failed(String)
    }

    @SwiftUI.State private var state: State = .idle

    var body: some View {
        Group {
            switch state {
            case .ready(let url):
                QuickLookPreviewView(url: url)
                    .background(.windowBackground)
            case .loading:
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.large)
                    Text("preview.loading")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .requiresClick(let sizeBytes):
                largeFilePrompt(sizeBytes: sizeBytes)
            case .failed(let message):
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text("preview.failed")
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("preview.retry") { Task { await load(force: true) } }
                        .buttonStyle(.bordered)
                }
            case .idle:
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: previewKey) { await load(force: false) }
    }

    private var previewKey: String {
        // Stable identifier so the .task fires exactly on a real change
        // (account, bucket, key, or etag).
        guard let account = viewModel.account, let bucket = viewModel.bucket else {
            return object.key
        }
        return PreviewCache.hash(
            accountID: account.id,
            bucket: bucket,
            key: object.key,
            etag: object.etag
        )
    }

    private func largeFilePrompt(sizeBytes: Int64) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("preview.large.title")
                .font(.headline)
            Text("preview.large.subtitle \(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("preview.large.action") {
                Task { await load(force: true) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func load(force: Bool) async {
        guard let account = viewModel.account, let bucket = viewModel.bucket else { return }
        // Cached? Skip every code path.
        if let cached = await container.previewCache.cachedURL(
            account: account,
            bucket: bucket,
            key: object.key,
            etag: object.etag
        ) {
            state = .ready(cached)
            return
        }
        if !force && !container.previewCache.qualifiesForAutoDownload(object) {
            state = .requiresClick(sizeBytes: object.size)
            return
        }
        state = .loading
        do {
            let url = try await container.previewCache.materialise(
                account: account,
                bucket: bucket,
                object: object
            )
            state = .ready(url)
        } catch is CancellationError {
            state = .idle
        } catch let error as BucketeerError {
            state = .failed(error.errorDescription ?? "")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
