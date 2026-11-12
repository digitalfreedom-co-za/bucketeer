//
//  EncryptionKeysView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import SwiftUI
import BucketeerCore

/// Settings → Encryption. Phase 13.15. Lists registered per-bucket
/// BYOK keys and offers add / delete actions. Encrypts transparently
/// on every upload / download to the corresponding bucket once a key
/// is registered.
struct EncryptionKeysView: View {
    @Environment(AppContainer.self) private var container
    @State private var reassigning: BucketEncryptionKey?
    @State private var creating: Bool = false
    @State private var pendingDeletion: BucketEncryptionKey?

    var body: some View {
        let viewModel = container.encryptionKeysViewModel
        VStack(spacing: 0) {
            if viewModel.keys.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(viewModel.keys) { key in
                        keyRow(key, viewModel: viewModel)
                            .contextMenu {
                                if viewModel.isOrphaned(key) {
                                    Button("encryption.reassign.action") { reassigning = key }
                                }
                                Button("action.delete", systemImage: "trash", role: .destructive) {
                                    pendingDeletion = key
                                }
                            }
                    }
                }
            }
            Divider()
            HStack {
                Button {
                    creating = true
                } label: {
                    Label("encryption.action.new", systemImage: "plus")
                }
                Spacer()
                if let error = viewModel.error {
                    Label(error.errorDescription ?? "\(error)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .padding(8)
            Text("encryption.warning")
                .font(.footnote)
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .frame(minWidth: 420, minHeight: 360)
        .task { await viewModel.reload() }
        .sheet(isPresented: $creating) {
            EncryptionKeyEditor(
                accounts: viewModel.accounts,
                existingKeys: viewModel.keys,
                listBuckets: { account in
                    try await viewModel.bucketNames(for: account)
                },
                verifyBucket: { bucket, account in
                    try await viewModel.verifyBucket(bucket, account: account)
                },
                onSave: { label, account, bucket in
                    try await viewModel.create(label: label, account: account, bucket: bucket)
                },
                finishCreation: { account, bucket in
                    try await viewModel.finishCreation(account: account, bucket: bucket)
                }
            )
        }
        .sheet(item: $reassigning) { key in
            EncryptionKeyReassignmentSheet(key: key, viewModel: viewModel)
        }
        .confirmationDialog(
            "encryption.delete.confirm.title",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { key in
            Button("action.delete", role: .destructive) {
                Task { await container.encryptionKeysViewModel.delete(key) }
                pendingDeletion = nil
            }
            Button("common.cancel", role: .cancel) { pendingDeletion = nil }
        } message: { key in
            Text("encryption.delete.confirm.message \(key.label)")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("encryption.empty.title", systemImage: "lock.shield")
        } description: {
            Text("encryption.empty.message")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func keyRow(_ key: BucketEncryptionKey, viewModel: EncryptionKeysViewModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.accentInk)
            VStack(alignment: .leading, spacing: 2) {
                Text(key.label).font(.callout.weight(.medium))
                Text("\(viewModel.accountName(for: key.accountID)) · \(key.bucket)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(key.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if viewModel.isOrphaned(key) {
                Button("encryption.reassign.action") { reassigning = key }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct EncryptionKeyEditor: View {
    let accounts: [S3Account]
    let existingKeys: [BucketEncryptionKey]
    let listBuckets: @Sendable (S3Account) async throws -> [String]
    let verifyBucket: @Sendable (String, S3Account) async throws -> Void
    let onSave: @Sendable (String, S3Account, String) async throws -> Void
    /// Retries only the refresh after `onSave` stored the key but
    /// failed to refresh the list or the File Provider mirror.
    let finishCreation: @Sendable (S3Account, String) async throws -> Void

    /// Where the bucket choice comes from. Manual entry is only offered
    /// when the account's buckets cannot be listed.
    private enum BucketSource {
        case noAccount
        case loading
        case listed([String])
        case manual(reason: String?)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var label: String = ""
    @State private var selectedAccount: S3Account?
    @State private var bucketSource: BucketSource = .noAccount
    @State private var selectedBucket: String?
    @State private var manualBucket: String = ""
    @State private var saving = false
    @State private var verifying = false
    @State private var keyCreated = false
    @State private var saveError: String?

    private var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedManualBucket: String {
        manualBucket.trimmingCharacters(in: .whitespaces)
    }

    /// Nil until a valid bucket is chosen: a listed one, or a manual
    /// name that passes the S3 naming rules.
    private var chosenBucket: String? {
        switch bucketSource {
        case .listed(let names):
            selectedBucket.flatMap { names.contains($0) ? $0 : nil }
        case .manual:
            S3BucketName.isValid(trimmedManualBucket) ? trimmedManualBucket : nil
        case .noAccount, .loading:
            nil
        }
    }

    private var chosenBucketHasKey: Bool {
        guard let account = selectedAccount, let bucket = chosenBucket else { return false }
        return existingKeys.contains { $0.accountID == account.id && $0.bucket == bucket }
    }

    private var canSave: Bool {
        if keyCreated { return !saving }
        return !saving && !trimmedLabel.isEmpty && selectedAccount != nil
            && chosenBucket != nil && !chosenBucketHasKey
    }

    private var isManualEntry: Bool {
        if case .manual = bucketSource { true } else { false }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("encryption.section.identity") {
                    TextField("encryption.field.label", text: $label)
                }
                .disabled(keyCreated || saving)
                Section("encryption.section.target") {
                    Picker("encryption.field.account", selection: $selectedAccount) {
                        Text("encryption.account.none").tag(S3Account?.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(S3Account?.some(account))
                        }
                    }
                    bucketField
                    if verifying {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("encryption.editor.verifyingBucket")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if chosenBucketHasKey, !keyCreated {
                        Text("encryption.editor.bucketHasKey")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
                .disabled(keyCreated || saving)
                Section {
                    Label("encryption.editor.warning", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("encryption.editor.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(keyCreated ? LocalizedStringKey("encryption.editor.retryRefresh") : LocalizedStringKey("action.create")) { save() }
                        .disabled(!canSave)
                }
            }
        }
        .interactiveDismissDisabled(saving)
        .frame(minWidth: 480, minHeight: 420)
        .task(id: selectedAccount?.id) { await loadBuckets() }
    }

    @ViewBuilder
    private var bucketField: some View {
        switch bucketSource {
        case .noAccount:
            bucketPicker(names: [])
                .disabled(true)
        case .loading:
            LabeledContent("encryption.field.bucket") {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("encryption.editor.loadingBuckets")
                        .foregroundStyle(.secondary)
                }
            }
        case .listed(let names):
            bucketPicker(names: names)
        case .manual(let reason):
            TextField("encryption.field.bucket", text: $manualBucket)
            VStack(alignment: .leading, spacing: 2) {
                Text("encryption.editor.bucketListUnavailable")
                if let reason {
                    Text(reason)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            if !trimmedManualBucket.isEmpty, !S3BucketName.isValid(trimmedManualBucket) {
                Text("encryption.editor.bucketInvalid")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
    }

    private func bucketPicker(names: [String]) -> some View {
        Picker("encryption.field.bucket", selection: $selectedBucket) {
            Text("encryption.bucket.none").tag(String?.none)
            ForEach(names, id: \.self) { name in
                Text(name).tag(String?.some(name))
            }
        }
    }

    /// Runs again whenever the account changes; `task(id:)` cancels
    /// the previous listing, so a slow reply cannot fill the picker
    /// with another account's buckets.
    private func loadBuckets() async {
        selectedBucket = nil
        saveError = nil
        guard let account = selectedAccount else {
            bucketSource = .noAccount
            return
        }
        bucketSource = .loading
        manualBucket = account.defaultBucket ?? ""
        do {
            let names = try await listBuckets(account)
            guard !Task.isCancelled else { return }
            bucketSource = names.isEmpty ? .manual(reason: nil) : .listed(names)
        } catch {
            guard !Task.isCancelled else { return }
            bucketSource = .manual(reason: error.localizedDescription)
        }
    }

    /// A manually entered bucket is verified before the key is created.
    /// Once the key is stored, a retry only refreshes the list and the
    /// mirror, so it never creates a second key.
    private func save() {
        guard let account = selectedAccount, let bucket = chosenBucket else { return }
        let validatedLabel = trimmedLabel
        saving = true
        saveError = nil
        Task {
            do {
                if keyCreated {
                    try await finishCreation(account, bucket)
                } else {
                    if isManualEntry {
                        verifying = true
                        defer { verifying = false }
                        try await verifyBucket(bucket, account)
                    }
                    try await onSave(validatedLabel, account, bucket)
                }
                dismiss()
            } catch let error as EncryptionKeyRefreshError {
                keyCreated = true
                saveError = error.localizedDescription
            } catch {
                saveError = error.localizedDescription
            }
            saving = false
        }
    }
}

private struct EncryptionKeyReassignmentSheet: View {
    let key: BucketEncryptionKey
    let viewModel: EncryptionKeysViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedAccount: S3Account?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("encryption.field.bucket", value: key.bucket)
                Picker("encryption.field.account", selection: $selectedAccount) {
                    Text("encryption.account.none").tag(S3Account?.none)
                    ForEach(viewModel.accounts) { account in
                        Text(account.name).tag(S3Account?.some(account))
                    }
                }
                if let error = viewModel.error {
                    Text(error.errorDescription ?? "\(error)")
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("encryption.reassign.action")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel", role: .cancel) { dismiss() }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("encryption.reassign.action") {
                        guard let account = selectedAccount else { return }
                        saving = true
                        Task {
                            if await viewModel.reassign(key, to: account) { dismiss() }
                            saving = false
                        }
                    }
                    .disabled(saving || selectedAccount == nil)
                }
            }
        }
        .interactiveDismissDisabled(saving)
        .frame(minWidth: 480, minHeight: 260)
        .task { await viewModel.reload() }
    }
}
