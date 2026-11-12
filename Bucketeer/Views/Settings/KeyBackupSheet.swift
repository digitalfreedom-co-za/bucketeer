import AppKit
import BucketeerCore
import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers

struct KeyBackupSheet: View {
    let viewModel: EncryptionKeysViewModel
    /// Nil imports; a nonempty selection exports these local keys.
    let exportIDs: Set<UUID>?
    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var plan: [KeyImportPlan]?
    @State private var replacements: Set<UUID> = []
    @State private var pendingReplacement: KeyImportPlan?
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedStringKey(exportIDs == nil ? "encryption.backup.import" : "encryption.backup.export"))
                .font(.headline)
            if let plan {
                List(plan) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.entry.label) · \(item.entry.bucket)")
                        Text(viewModel.accountName(for: item.entry.accountID))
                            .foregroundStyle(.secondary)
                        Text(stateLabel(item.state)).font(.caption)
                        if item.state == .conflict {
                            Toggle("encryption.backup.replace", isOn: Binding(
                                get: { replacements.contains(item.id) },
                                set: { value in
                                    if value { pendingReplacement = item }
                                    else { replacements.remove(item.id) }
                                }
                            ))
                            if !replacements.contains(item.id) {
                                Text("encryption.backup.keep").font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 220)
            } else {
                SecureField("encryption.backup.passphrase", text: $passphrase)
                if exportIDs != nil {
                    SecureField("encryption.backup.confirmation", text: $confirmation)
                    Text("encryption.backup.hint").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Text("encryption.backup.warning").font(.footnote).foregroundStyle(.orange)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            HStack {
                Button("action.cancel", role: .cancel) { clearSecrets(); dismiss() }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(LocalizedStringKey(exportIDs == nil ? "encryption.backup.import" : "encryption.backup.export")) {
                    perform()
                }
                .disabled(!canProceed)
            }
        }
        .padding(20)
        .frame(width: 540)
        .disabled(busy)
        .interactiveDismissDisabled(busy)
        .confirmationDialog("encryption.backup.replaceWarning", isPresented: Binding(
            get: { pendingReplacement != nil },
            set: { if !$0 { pendingReplacement = nil } }
        ), titleVisibility: .visible) {
            Button("encryption.backup.replace", role: .destructive) {
                if let pendingReplacement { replacements.insert(pendingReplacement.id) }
                pendingReplacement = nil
            }
            Button("action.cancel", role: .cancel) { pendingReplacement = nil }
        } message: {
            if let pendingReplacement {
                Text("\(pendingReplacement.entry.label) · \(pendingReplacement.entry.bucket)")
            }
        }
        .onDisappear { clearSecrets() }
    }

    private var canProceed: Bool {
        guard !busy else { return false }
        if plan != nil { return true }
        if exportIDs != nil { return passphrase.count >= 12 && passphrase == confirmation }
        return !passphrase.isEmpty
    }

    private func stateLabel(_ state: KeyImportPlan.State) -> LocalizedStringKey {
        switch state {
        case .new: "encryption.backup.new"
        case .identical: "encryption.backup.identical"
        case .conflict: "encryption.backup.conflict"
        case .unknownAccount: "encryption.account.deleted"
        }
    }

    private func clearSecrets() {
        passphrase = ""
        confirmation = ""
        plan = nil
    }

    private func perform() {
        busy = true
        errorMessage = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                if let exportIDs {
                    // Authenticate immediately before reading any key material.
                    let context = LAContext()
                    guard try await context.evaluatePolicy(.deviceOwnerAuthentication,
                        localizedReason: String(localized: "encryption.backup.authenticate")) else { return }
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [UTType(filenameExtension: "bktkeys") ?? .data]
                    panel.nameFieldStringValue = "Bucketeer.bktkeys"
                    panel.canCreateDirectories = true
                    guard await panel.begin() == .OK, let url = panel.url else { return }
                    try await viewModel.exportKeys(ids: exportIDs, passphrase: passphrase, confirmation: confirmation, to: url)
                } else if let plan {
                    try await viewModel.importKeys(plan, replacements: replacements)
                } else {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [UTType(filenameExtension: "bktkeys") ?? .data]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    guard await panel.begin() == .OK, let url = panel.url else { return }
                    plan = try await viewModel.planImport(from: url, passphrase: passphrase)
                    passphrase = ""
                    return
                }
                clearSecrets()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension EncryptionKeysViewModel {
    /// The shared transfer gate invokes this only for a key without a saved
    /// backup or prior acknowledgement. Cancellation leaves the transfer blocked.
    static func confirmBackupRisk(_ key: BucketEncryptionKey) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = key.label + " · " + key.bucket
        alert.informativeText = String(localized: "encryption.backup.warning")
        alert.addButton(withTitle: String(localized: "action.cancel"))
        alert.addButton(withTitle: String(localized: "encryption.backup.acknowledge"))
        return alert.runModal() == .alertSecondButtonReturn
    }
}
