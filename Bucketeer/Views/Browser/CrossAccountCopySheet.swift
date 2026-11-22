//
//  CrossAccountCopySheet.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import SwiftUI
import BucketeerCore

/// Destination picker for a cross-account copy / move. Phase 13.14.
struct CrossAccountCopySheet: View {
    let sourceAccount: S3Account
    let sourceBucket: String
    let keys: [String]
    let accounts: [S3Account]
    /// Whether the copy would store decrypted files in a bucket without a key.
    let isEncryptedToPlain: @Sendable (_ destAccount: S3Account, _ destBucket: String) async -> Bool
    let onSubmit: @Sendable (
        _ destAccount: S3Account,
        _ destBucket: String,
        _ destPrefix: String,
        _ keepSource: Bool,
        _ allowsDecryptedCopies: Bool
    ) async -> [(key: String, error: BucketeerError?)]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedAccount: S3Account?
    @State private var destinationBucket: String = ""
    @State private var destinationPrefix: String = ""
    @State private var keepSource: Bool = true
    @State private var inFlight: Bool = false
    @State private var resultSummary: String?
    @State private var confirmingUnencryptedCopy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("crossCopy.section.source") {
                    LabeledContent("crossCopy.field.account") {
                        Text("\(sourceAccount.name) (\(sourceAccount.provider.localizedDisplayName))")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("crossCopy.field.bucket") {
                        Text(sourceBucket).foregroundStyle(.secondary)
                    }
                    LabeledContent("crossCopy.field.count") {
                        Text("\(keys.count)").foregroundStyle(.secondary)
                    }
                }
                Section("crossCopy.section.destination") {
                    Picker("crossCopy.field.account", selection: $selectedAccount) {
                        Text("crossCopy.account.none").tag(S3Account?.none)
                        ForEach(otherAccounts) { account in
                            Text("\(account.name) — \(account.provider.localizedDisplayName)")
                                .tag(S3Account?.some(account))
                        }
                    }
                    TextField("crossCopy.field.bucket", text: $destinationBucket)
                        .textFieldStyle(.roundedBorder)
                    TextField("crossCopy.field.prefix", text: $destinationPrefix)
                        .textFieldStyle(.roundedBorder)
                    Text("crossCopy.prefix.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("crossCopy.section.options") {
                    Toggle("crossCopy.field.keepSource", isOn: $keepSource)
                    if let selectedAccount {
                        let serverSide = CrossAccountCopyCoordinator.canServerSideCopy(
                            from: sourceAccount, to: selectedAccount
                        )
                        Label(
                            serverSide
                                ? "crossCopy.path.serverSide"
                                : "crossCopy.path.roundTrip",
                            systemImage: serverSide ? "bolt.fill" : "arrow.up.arrow.down"
                        )
                        .font(.footnote)
                        .foregroundStyle(serverSide ? .green : .orange)
                    }
                }
                if let resultSummary {
                    Section {
                        Text(resultSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("crossCopy.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.copy") { Task { await submit() } }
                        .disabled(!isValid || inFlight)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 460)
        .alert("encryption.plainCopy.title", isPresented: $confirmingUnencryptedCopy) {
            Button("action.cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("encryption.plainCopy.confirm", role: .destructive) {
                Task { await copy(allowsDecryptedCopies: true) }
            }
        } message: {
            Text("encryption.plainCopy.message \(sourceBucket) \(trimmedDestinationBucket)")
        }
    }

    // MARK: - Helpers

    private var otherAccounts: [S3Account] {
        accounts.filter { $0.id != sourceAccount.id }
    }

    private var isValid: Bool {
        selectedAccount != nil && !trimmedDestinationBucket.isEmpty
    }

    private var trimmedDestinationBucket: String {
        destinationBucket.trimmingCharacters(in: .whitespaces)
    }

    /// Asks once for the whole selection before anything is decrypted
    /// into a bucket without a key.
    private func submit() async {
        guard let selectedAccount else { return }
        inFlight = true
        let needsConfirmation = await isEncryptedToPlain(selectedAccount, trimmedDestinationBucket)
        inFlight = false
        if needsConfirmation {
            confirmingUnencryptedCopy = true
        } else {
            await copy(allowsDecryptedCopies: false)
        }
    }

    private func copy(allowsDecryptedCopies: Bool) async {
        guard let selectedAccount else { return }
        inFlight = true
        defer { inFlight = false }
        let outcomes = await onSubmit(
            selectedAccount,
            trimmedDestinationBucket,
            destinationPrefix.trimmingCharacters(in: .whitespaces),
            keepSource,
            allowsDecryptedCopies
        )
        let failed = outcomes.filter { $0.error != nil }
        if failed.isEmpty {
            resultSummary = String(
                format: NSLocalizedString("crossCopy.summary.success", comment: ""),
                outcomes.count
            )
            dismiss()
        } else {
            resultSummary = String(
                format: NSLocalizedString("crossCopy.summary.partial", comment: ""),
                outcomes.count - failed.count,
                failed.count
            )
        }
    }
}
