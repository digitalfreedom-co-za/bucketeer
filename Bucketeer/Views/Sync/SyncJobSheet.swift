//
//  SyncJobSheet.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import SwiftUI
import AppKit
import BucketeerCore

/// Single-page sync job editor. Each side (source / destination) can be
/// either an S3 / Azure account scope or a local folder. Phase 9.8 —
/// local folder support uses security-scoped bookmarks so the access
/// survives across launches.
struct SyncJobSheet: View {
    enum Mode: Equatable {
        case create
        case edit(SyncJob)
    }

    let mode: Mode
    let accounts: [S3Account]
    let onSave: @MainActor (SyncJob) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var mode_: SyncMode = .copy

    // Per-side endpoint editor state. Kind drives which subset of
    // fields the form shows; the unused fields keep their values so
    // switching back doesn't lose user input mid-edit.
    @State private var sourceKind: EndpointKind = .s3
    @State private var sourceAccountID: UUID?
    @State private var sourceBucket: String = ""
    @State private var sourcePrefix: String = ""
    @State private var sourceLocalBookmark: Data?
    @State private var sourceLocalDisplayPath: String = ""

    @State private var destKind: EndpointKind = .s3
    @State private var destAccountID: UUID?
    @State private var destBucket: String = ""
    @State private var destPrefix: String = ""
    @State private var destLocalBookmark: Data?
    @State private var destLocalDisplayPath: String = ""

    @State private var diffStrategy: SyncDiffStrategy = .nameAndSize
    @State private var includeGlobs: String = ""
    @State private var excludeGlobs: String = ""
    @State private var deletePropagation: Bool = false
    @State private var scheduleKind: ScheduleKind = .manual
    @State private var intervalMinutes: Int = 60
    @State private var concurrency: Int = 4
    @State private var enabled: Bool = true
    @State private var hasHydrated: Bool = false
    @State private var saving: Bool = false

    private enum ScheduleKind: String, CaseIterable {
        case manual, onLaunch, interval
    }

    private enum EndpointKind: String, CaseIterable {
        case s3
        case localFolder
    }

    private var isEditing: Bool { if case .edit = mode { return true }; return false }

    private var canSave: Bool {
        guard !saving,
              !name.trimmingCharacters(in: .whitespaces).isEmpty
        else { return false }
        return endpointValid(
            kind: sourceKind,
            accountID: sourceAccountID,
            bucket: sourceBucket,
            bookmark: sourceLocalBookmark
        ) && endpointValid(
            kind: destKind,
            accountID: destAccountID,
            bucket: destBucket,
            bookmark: destLocalBookmark
        )
    }

    private func endpointValid(
        kind: EndpointKind,
        accountID: UUID?,
        bucket: String,
        bookmark: Data?
    ) -> Bool {
        switch kind {
        case .s3:
            return accountID != nil
                && !bucket.trimmingCharacters(in: .whitespaces).isEmpty
        case .localFolder:
            return bookmark != nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                endpointSection(
                    titleKey: "sync.section.source",
                    kind: $sourceKind,
                    accountID: $sourceAccountID,
                    bucket: $sourceBucket,
                    prefix: $sourcePrefix,
                    bookmark: $sourceLocalBookmark,
                    displayPath: $sourceLocalDisplayPath
                )
                endpointSection(
                    titleKey: "sync.section.destination",
                    kind: $destKind,
                    accountID: $destAccountID,
                    bucket: $destBucket,
                    prefix: $destPrefix,
                    bookmark: $destLocalBookmark,
                    displayPath: $destLocalDisplayPath
                )
                rulesSection
                scheduleSection
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "sync.edit.title" : "sync.new.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { commit() }
                        .disabled(!canSave)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .onAppear(perform: hydrate)
        }
        .frame(minWidth: 620, minHeight: 660)
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section("sync.section.general") {
            TextField("sync.field.name", text: $name)
            Picker("sync.field.mode", selection: $mode_) {
                Text("sync.mode.copy").tag(SyncMode.copy)
                Text("sync.mode.move").tag(SyncMode.move)
                Text("sync.mode.mirror").tag(SyncMode.mirror)
            }
            Toggle("sync.field.enabled", isOn: $enabled)
        }
    }

    @ViewBuilder
    private func endpointSection(
        titleKey: LocalizedStringKey,
        kind: Binding<EndpointKind>,
        accountID: Binding<UUID?>,
        bucket: Binding<String>,
        prefix: Binding<String>,
        bookmark: Binding<Data?>,
        displayPath: Binding<String>
    ) -> some View {
        Section(titleKey) {
            Picker("sync.field.endpointKind", selection: kind) {
                Text("sync.endpoint.s3").tag(EndpointKind.s3)
                Text("sync.endpoint.localFolder").tag(EndpointKind.localFolder)
            }
            switch kind.wrappedValue {
            case .s3:
                accountPicker(selection: accountID)
                TextField("sync.field.bucket", text: bucket)
                    .autocorrectionDisabled()
                TextField("sync.field.prefix", text: prefix)
                    .autocorrectionDisabled()
            case .localFolder:
                HStack(spacing: 12) {
                    Image(systemName: bookmark.wrappedValue == nil
                          ? "folder.badge.questionmark"
                          : "folder.fill")
                        .foregroundStyle(bookmark.wrappedValue == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("sync.field.localFolder")
                            .font(.callout)
                        Text(displayPath.wrappedValue.isEmpty
                             ? String(localized: "sync.localFolder.notChosen",
                                      defaultValue: "No folder selected")
                             : displayPath.wrappedValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("sync.action.chooseFolder") {
                        chooseFolder(into: bookmark, displayPath: displayPath)
                    }
                }
            }
        }
    }

    private var rulesSection: some View {
        Section("sync.section.rules") {
            Picker("sync.field.diffStrategy", selection: $diffStrategy) {
                Text("sync.diff.nameAndSize").tag(SyncDiffStrategy.nameAndSize)
                Text("sync.diff.nameAndEtag").tag(SyncDiffStrategy.nameAndEtag)
            }
            if isAnyLocal {
                Text("sync.diff.localHint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            TextField("sync.field.includeGlobs", text: $includeGlobs, prompt: Text("*.jpg, *.pdf"))
                .autocorrectionDisabled()
            TextField("sync.field.excludeGlobs", text: $excludeGlobs, prompt: Text("*.tmp, *.log"))
                .autocorrectionDisabled()
            if mode_ == .mirror {
                Toggle("sync.field.deletePropagation", isOn: $deletePropagation)
                Text("sync.delete.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Stepper(value: $concurrency, in: 1...8) {
                Text("sync.field.concurrency \(concurrency)")
            }
        }
    }

    private var scheduleSection: some View {
        Section("sync.section.schedule") {
            Picker("sync.field.schedule", selection: $scheduleKind) {
                Text("sync.schedule.manual").tag(ScheduleKind.manual)
                Text("sync.schedule.onLaunch").tag(ScheduleKind.onLaunch)
                Text("sync.schedule.interval").tag(ScheduleKind.interval)
            }
            if scheduleKind == .interval {
                Stepper(value: $intervalMinutes, in: 5...1440, step: 5) {
                    Text("sync.field.intervalMinutes \(intervalMinutes)")
                }
            }
        }
    }

    /// Either side picked as local — used to surface the ETag-not-
    /// available hint in the rules section.
    private var isAnyLocal: Bool {
        sourceKind == .localFolder || destKind == .localFolder
    }

    @ViewBuilder
    private func accountPicker(selection: Binding<UUID?>) -> some View {
        Picker("sync.field.account", selection: selection) {
            Text("sync.account.placeholder").tag(UUID?.none)
            ForEach(accounts) { account in
                Label {
                    Text("\(account.name) (\(account.provider.displayName))")
                } icon: {
                    Image(systemName: account.provider.iconSystemName)
                }
                .tag(Optional(account.id))
            }
        }
    }

    // MARK: - Folder picker

    /// Open an NSOpenPanel for directory selection. On OK we capture a
    /// security-scoped bookmark so the access persists across launches
    /// (App Sandbox requirement) and store the display path for the
    /// list rows. Errors surface in-place via the UI's empty-state line.
    private func chooseFolder(
        into bookmark: Binding<Data?>,
        displayPath: Binding<String>
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(
            localized: "sync.localFolder.pickerMessage",
            defaultValue: "Choose a folder for Bucketeer to sync."
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            bookmark.wrappedValue = data
            displayPath.wrappedValue = url.path(percentEncoded: false)
        } catch {
            bookmark.wrappedValue = nil
            displayPath.wrappedValue = ""
        }
    }

    // MARK: - Hydrate / commit

    private func hydrate() {
        guard !hasHydrated else { return }
        defer { hasHydrated = true }
        if case .edit(let job) = mode {
            name = job.name
            mode_ = job.mode
            hydrateEndpoint(
                job.source,
                kind: $sourceKind,
                accountID: $sourceAccountID,
                bucket: $sourceBucket,
                prefix: $sourcePrefix,
                bookmark: $sourceLocalBookmark,
                displayPath: $sourceLocalDisplayPath
            )
            hydrateEndpoint(
                job.destination,
                kind: $destKind,
                accountID: $destAccountID,
                bucket: $destBucket,
                prefix: $destPrefix,
                bookmark: $destLocalBookmark,
                displayPath: $destLocalDisplayPath
            )
            diffStrategy = job.diffStrategy
            includeGlobs = job.includeGlobs.joined(separator: ", ")
            excludeGlobs = job.excludeGlobs.joined(separator: ", ")
            deletePropagation = job.deletePropagation
            switch job.schedule {
            case .manual:                scheduleKind = .manual
            case .onLaunch:              scheduleKind = .onLaunch
            case .interval(let seconds): scheduleKind = .interval
                                         intervalMinutes = max(5, seconds / 60)
            }
            concurrency = job.concurrency
            enabled = job.enabled
        } else if let first = accounts.first {
            sourceAccountID = first.id
            destAccountID = first.id
        }
    }

    private func hydrateEndpoint(
        _ endpoint: SyncEndpoint,
        kind: Binding<EndpointKind>,
        accountID: Binding<UUID?>,
        bucket: Binding<String>,
        prefix: Binding<String>,
        bookmark: Binding<Data?>,
        displayPath: Binding<String>
    ) {
        switch endpoint {
        case .s3(let aid, let b, let p):
            kind.wrappedValue = .s3
            accountID.wrappedValue = aid
            bucket.wrappedValue = b
            prefix.wrappedValue = p
        case .localFolder(let bm, let path):
            kind.wrappedValue = .localFolder
            bookmark.wrappedValue = bm
            displayPath.wrappedValue = path
        }
    }

    private func commit() {
        let source = buildEndpoint(
            kind: sourceKind,
            accountID: sourceAccountID,
            bucket: sourceBucket,
            prefix: sourcePrefix,
            bookmark: sourceLocalBookmark,
            displayPath: sourceLocalDisplayPath
        )
        let destination = buildEndpoint(
            kind: destKind,
            accountID: destAccountID,
            bucket: destBucket,
            prefix: destPrefix,
            bookmark: destLocalBookmark,
            displayPath: destLocalDisplayPath
        )
        guard let source, let destination else { return }
        saving = true
        let job = SyncJob(
            id: { if case .edit(let j) = mode { return j.id }; return UUID() }(),
            name: name.trimmingCharacters(in: .whitespaces),
            mode: mode_,
            source: source,
            destination: destination,
            diffStrategy: diffStrategy,
            includeGlobs: splitGlobs(includeGlobs),
            excludeGlobs: splitGlobs(excludeGlobs),
            deletePropagation: deletePropagation,
            schedule: {
                switch scheduleKind {
                case .manual:   return .manual
                case .onLaunch: return .onLaunch
                case .interval: return .interval(seconds: intervalMinutes * 60)
                }
            }(),
            concurrency: concurrency,
            enabled: enabled
        )
        Task {
            await onSave(job)
            dismiss()
        }
    }

    private func buildEndpoint(
        kind: EndpointKind,
        accountID: UUID?,
        bucket: String,
        prefix: String,
        bookmark: Data?,
        displayPath: String
    ) -> SyncEndpoint? {
        switch kind {
        case .s3:
            guard let accountID else { return nil }
            return .s3(
                accountID: accountID,
                bucket: bucket.trimmingCharacters(in: .whitespaces),
                prefix: normalise(prefix: prefix)
            )
        case .localFolder:
            guard let bookmark else { return nil }
            return .localFolder(bookmark: bookmark, displayPath: displayPath)
        }
    }

    private func splitGlobs(_ raw: String) -> [String] {
        raw
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalise(prefix: String) -> String {
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }
        return trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
    }
}
