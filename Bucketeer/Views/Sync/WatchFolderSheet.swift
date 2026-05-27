//
//  WatchFolderSheet.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import SwiftUI
import AppKit
import BucketeerCore

/// Streamlined creation sheet for a **watch folder** — a sync job
/// with a local-folder source, an S3 / Azure destination, and an
/// `.onLocalChange` schedule. Reuses the existing sync engine end-to-
/// end; this view exists only to spare the user the full multi-mode
/// SyncJobSheet when all they want is "auto-upload everything that
/// lands in this folder". Phase 13.3.
struct WatchFolderSheet: View {
    let accounts: [S3Account]
    let onSave: @Sendable (SyncJob) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var folderBookmark: Data?
    @State private var folderDisplayPath: String = ""
    @State private var selectedAccount: S3Account?
    @State private var bucket: String = ""
    @State private var prefix: String = ""
    @State private var deleteAfterUpload: Bool = false
    @State private var inFlight: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("watchFolder.section.name") {
                    TextField("watchFolder.field.name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                Section("watchFolder.section.source") {
                    HStack {
                        Text(folderDisplayPath.isEmpty
                             ? String(localized: "watchFolder.source.pickPrompt",
                                      defaultValue: "Pick a folder…")
                             : folderDisplayPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(folderDisplayPath.isEmpty ? .secondary : .primary)
                        Spacer()
                        Button("watchFolder.action.chooseFolder") { pickFolder() }
                    }
                }
                Section("watchFolder.section.destination") {
                    Picker("watchFolder.field.account", selection: $selectedAccount) {
                        Text("watchFolder.account.none").tag(S3Account?.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(S3Account?.some(account))
                        }
                    }
                    TextField("watchFolder.field.bucket", text: $bucket)
                        .textFieldStyle(.roundedBorder)
                    TextField("watchFolder.field.prefix", text: $prefix)
                        .textFieldStyle(.roundedBorder)
                    Text("watchFolder.prefix.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("watchFolder.section.options") {
                    Toggle("watchFolder.field.deleteAfterUpload", isOn: $deleteAfterUpload)
                    Text("watchFolder.deleteAfterUpload.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let message = errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("watchFolder.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { Task { await save() } }
                        .disabled(!isValid || inFlight)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 460)
    }

    // MARK: - Actions

    /// Security-scoped folder picker that produces the bookmark blob
    /// the sync engine needs to survive across launches.
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "watchFolder.action.chooseFolder",
                              defaultValue: "Choose Folder")
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let bookmark = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                folderBookmark = bookmark
                folderDisplayPath = url.path
                if name.isEmpty {
                    // `String(localized:)` requires a StaticString key,
                    // so use the %@-format pattern stored under
                    // `watchFolder.defaultName` (e.g. "Watch %@") and
                    // interpolate the folder name through `String(format:)`.
                    name = String(
                        format: NSLocalizedString("watchFolder.defaultName", comment: ""),
                        url.lastPathComponent
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        folderBookmark != nil &&
        selectedAccount != nil &&
        !bucket.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() async {
        guard let folderBookmark, let selectedAccount, isValid else { return }
        inFlight = true
        defer { inFlight = false }

        let normalisedPrefix: String = {
            let trimmed = prefix.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return "" }
            return trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
        }()

        let job = SyncJob(
            name: name.trimmingCharacters(in: .whitespaces),
            // `.move` deletes the local source file after a
            // successful upsert — exactly the "hot folder" semantic.
            mode: deleteAfterUpload ? .move : .copy,
            source: .localFolder(bookmark: folderBookmark, displayPath: folderDisplayPath),
            destination: .s3(
                accountID: selectedAccount.id,
                bucket: bucket.trimmingCharacters(in: .whitespaces),
                prefix: normalisedPrefix
            ),
            // Watch folders always trigger on local change. Setting
            // the schedule here ensures the SyncEngine starts an
            // FSEvents watcher when the job is saved.
            schedule: .onLocalChange,
            concurrency: 4,
            enabled: true
        )
        await onSave(job)
        dismiss()
    }
}
