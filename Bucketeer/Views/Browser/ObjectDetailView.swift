//
//  ObjectDetailView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI

struct ObjectDetailView: View {
    @Bindable var viewModel: BrowserViewModel

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
