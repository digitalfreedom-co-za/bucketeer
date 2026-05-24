//
//  ActivityLogView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import SwiftUI
import UniformTypeIdentifiers
import BucketeerCore

/// User-facing audit log. Lists every recorded activity row with
/// search + kind + account filters and offers CSV export plus
/// "Clear all".
///
/// The view stays read-only — no row-level editing. Phase 13.1.
struct ActivityLogView: View {
    @Environment(AppContainer.self) private var container

    @State private var pendingClear: Bool = false
    @State private var exportTarget: ExportTarget?

    var body: some View {
        @Bindable var viewModel = container.activityLogViewModel
        VStack(spacing: 0) {
            filterBar
            Divider()
            if viewModel.entries.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                tableContent
            }
            Divider()
            footer
        }
        .toolbar { toolbarContent }
        .task { await viewModel.reload() }
        .onChange(of: viewModel.searchText) { _, _ in Task { await viewModel.reload() } }
        .onChange(of: viewModel.accountFilter) { _, _ in Task { await viewModel.reload() } }
        .onChange(of: viewModel.kindFilter) { _, _ in Task { await viewModel.reload() } }
        .confirmationDialog(
            "activity.clear.confirm.title",
            isPresented: $pendingClear,
            titleVisibility: .visible
        ) {
            Button("activity.clear.confirm.button", role: .destructive) {
                Task { await viewModel.deleteAll() }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("activity.clear.confirm.message")
        }
        .fileExporter(
            isPresented: Binding(
                get: { exportTarget != nil },
                set: { if !$0 { exportTarget = nil } }
            ),
            document: exportTarget?.document,
            contentType: .commaSeparatedText,
            defaultFilename: exportTarget?.filename ?? "BucketeerActivity"
        ) { _ in
            exportTarget = nil
        }
    }

    // MARK: - Subviews

    private var filterBar: some View {
        @Bindable var viewModel = container.activityLogViewModel
        return HStack(spacing: 12) {
            TextField("activity.search.placeholder", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
            Picker("activity.filter.account", selection: $viewModel.accountFilter) {
                Text("activity.filter.account.any").tag(UUID?.none)
                ForEach(viewModel.accounts) { account in
                    Text(account.name).tag(UUID?.some(account.id))
                }
            }
            .frame(maxWidth: 220)
            kindFilterMenu
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var kindFilterMenu: some View {
        @Bindable var viewModel = container.activityLogViewModel
        return Menu {
            Button("activity.filter.kind.all") {
                viewModel.kindFilter = []
            }
            Divider()
            ForEach(ActivityKind.allCases, id: \.rawValue) { kind in
                let isOn = viewModel.kindFilter.contains(kind)
                Button {
                    if isOn {
                        viewModel.kindFilter.remove(kind)
                    } else {
                        viewModel.kindFilter.insert(kind)
                    }
                } label: {
                    Label {
                        Text(Self.label(for: kind))
                    } icon: {
                        if isOn { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            let count = container.activityLogViewModel.kindFilter.count
            if count == 0 {
                Label("activity.filter.kind.all", systemImage: "line.3.horizontal.decrease.circle")
            } else {
                Label(
                    String(
                        format: NSLocalizedString("activity.filter.kind.count", comment: ""),
                        count
                    ),
                    systemImage: "line.3.horizontal.decrease.circle.fill"
                )
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var tableContent: some View {
        Table(container.activityLogViewModel.entries) {
            TableColumn("activity.column.time") { entry in
                Text(entry.createdAt, style: .time)
                    .font(.callout)
                    .help(Self.fullDate(entry.createdAt))
            }
            .width(min: 70, ideal: 90)

            TableColumn("activity.column.kind") { entry in
                Label(Self.label(for: entry.kind), systemImage: Self.systemImage(for: entry.kind))
                    .labelStyle(.titleAndIcon)
            }
            .width(min: 140, ideal: 180)

            TableColumn("activity.column.status") { entry in
                statusBadge(for: entry.status)
            }
            .width(min: 90, ideal: 110)

            TableColumn("activity.column.account") { entry in
                Text(entry.accountName ?? "—")
            }
            .width(min: 100, ideal: 140)

            TableColumn("activity.column.target") { entry in
                VStack(alignment: .leading, spacing: 2) {
                    if let bucket = entry.bucket {
                        Text(bucket).font(.callout.weight(.medium))
                    }
                    if let key = entry.key {
                        Text(key).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    if let job = entry.syncJobName {
                        Text(job).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 200, ideal: 320)

            TableColumn("activity.column.details") { entry in
                if let error = entry.errorMessage {
                    Text(error).foregroundStyle(.red).lineLimit(2)
                } else if let message = entry.message {
                    Text(message).foregroundStyle(.secondary).lineLimit(2)
                } else if let bytes = entry.byteCount {
                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                        .foregroundStyle(.secondary)
                } else {
                    Text("").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            let viewModel = container.activityLogViewModel
            Text(
                String(
                    format: NSLocalizedString("activity.footer.showing", comment: ""),
                    viewModel.entries.count,
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("activity.empty.title")
                .font(.headline)
            Text("activity.empty.subtitle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await container.activityLogViewModel.reload() }
            } label: {
                Label("common.refresh", systemImage: "arrow.clockwise")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                exportTarget = ExportTarget(
                    text: container.activityLogViewModel.csvExport(),
                    filename: "BucketeerActivity-\(Self.timestamp()).csv"
                )
            } label: {
                Label("activity.action.export", systemImage: "square.and.arrow.up")
            }
        }
        ToolbarItem(placement: .destructiveAction) {
            Button(role: .destructive) {
                pendingClear = true
            } label: {
                Label("activity.action.clear", systemImage: "trash")
            }
            .disabled(container.activityLogViewModel.entries.isEmpty)
        }
    }

    // MARK: - Helpers

    private func statusBadge(for status: ActivityStatus) -> some View {
        let (label, colour): (LocalizedStringKey, Color) = {
            switch status {
            case .info:       return ("activity.status.info", .gray)
            case .success:    return ("activity.status.success", .green)
            case .failure:    return ("activity.status.failure", .red)
            case .cancelled:  return ("activity.status.cancelled", .orange)
            }
        }()
        return Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(colour.opacity(0.18))
            )
            .foregroundStyle(colour)
    }

    static func label(for kind: ActivityKind) -> LocalizedStringKey {
        switch kind {
        case .upload:               return "activity.kind.upload"
        case .download:             return "activity.kind.download"
        case .delete:               return "activity.kind.delete"
        case .createFolder:         return "activity.kind.createFolder"
        case .copy:                 return "activity.kind.copy"
        case .presignedURL:         return "activity.kind.presignedURL"
        case .syncRunStarted:       return "activity.kind.syncRunStarted"
        case .syncRunFinished:      return "activity.kind.syncRunFinished"
        case .syncRunFailed:        return "activity.kind.syncRunFailed"
        case .syncRunCancelled:     return "activity.kind.syncRunCancelled"
        case .accountAdded:         return "activity.kind.accountAdded"
        case .accountUpdated:       return "activity.kind.accountUpdated"
        case .accountDeleted:       return "activity.kind.accountDeleted"
        case .mountInstalled:       return "activity.kind.mountInstalled"
        case .mountUninstalled:     return "activity.kind.mountUninstalled"
        case .watchFolderTriggered: return "activity.kind.watchFolderTriggered"
        }
    }

    static func systemImage(for kind: ActivityKind) -> String {
        switch kind {
        case .upload:               return "arrow.up.circle"
        case .download:             return "arrow.down.circle"
        case .delete:               return "trash"
        case .createFolder:         return "folder.badge.plus"
        case .copy:                 return "document.on.document"
        case .presignedURL:         return "link"
        case .syncRunStarted:       return "arrow.triangle.2.circlepath"
        case .syncRunFinished:      return "checkmark.circle"
        case .syncRunFailed:        return "exclamationmark.triangle"
        case .syncRunCancelled:     return "stop.circle"
        case .accountAdded:         return "person.crop.circle.badge.plus"
        case .accountUpdated:       return "person.crop.circle.badge.checkmark"
        case .accountDeleted:       return "person.crop.circle.badge.minus"
        case .mountInstalled:       return "externaldrive.connected.to.line.below"
        case .mountUninstalled:     return "externaldrive.badge.minus"
        case .watchFolderTriggered: return "eye"
        }
    }

    private static func fullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f.string(from: date)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}

/// CSV document wrapper for `.fileExporter`. Tracks the filename so
/// the same target type can be used for re-exports without leaking
/// the previous content.
private struct ExportTarget {
    let text: String
    let filename: String

    var document: CSVDocument { CSVDocument(text: text) }
}

private struct CSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]
    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let string = String(data: data, encoding: .utf8) {
            self.text = string
        } else {
            self.text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
