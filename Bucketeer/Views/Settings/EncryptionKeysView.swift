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
                onSave: { label, account, bucket in
                    await viewModel.create(label: label, account: account, bucket: bucket)
                }
            )
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
                .foregroundStyle(.tint)
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
        }
        .padding(.vertical, 4)
    }
}

private struct EncryptionKeyEditor: View {
    let accounts: [S3Account]
    let onSave: @Sendable (String, S3Account, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label: String = ""
    @State private var selectedAccount: S3Account?
    @State private var bucket: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("encryption.section.identity") {
                    TextField("encryption.field.label", text: $label)
                }
                Section("encryption.section.target") {
                    Picker("encryption.field.account", selection: $selectedAccount) {
                        Text("encryption.account.none").tag(S3Account?.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(S3Account?.some(account))
                        }
                    }
                    TextField("encryption.field.bucket", text: $bucket)
                }
                Section {
                    Label("encryption.editor.warning", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("encryption.editor.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.create") {
                        guard let account = selectedAccount else { return }
                        Task {
                            await onSave(
                                label.trimmingCharacters(in: .whitespaces),
                                account,
                                bucket.trimmingCharacters(in: .whitespaces)
                            )
                            dismiss()
                        }
                    }
                    .disabled(
                        label.trimmingCharacters(in: .whitespaces).isEmpty
                        || bucket.trimmingCharacters(in: .whitespaces).isEmpty
                        || selectedAccount == nil
                    )
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }
}
