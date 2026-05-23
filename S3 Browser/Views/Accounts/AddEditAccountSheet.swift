//
//  AddEditAccountSheet.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI
import LocalAuthentication

struct AddEditAccountSheet: View {
    enum Mode: Equatable {
        case create
        case edit(S3Account)
    }

    let mode: Mode
    /// Returns `nil` on success; an error to surface inline on failure.
    let onSave: @MainActor (S3Account, AccountCredentials) async -> S3BrowserError?
    /// Returns `nil` on a successful connection, an error otherwise.
    /// Optional: when omitted the Test Connection button is hidden.
    var onTest: (@MainActor (S3Account, AccountCredentials) async -> S3BrowserError?)?
    /// Returns the stored credentials for an account, or nil if the
    /// Keychain lookup fails. Required for the "Reveal stored secret"
    /// flow in edit mode.
    var onLoadCredentials: (@MainActor (UUID) async -> AccountCredentials?)?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var provider: S3Provider = .awsS3
    @State private var region: String = ""
    @State private var endpointOverride: String = ""
    @State private var accountIdentifier: String = ""
    @State private var defaultBucket: String = ""
    @State private var usesPathStyle: Bool = false
    @State private var accessKey: String = ""
    @State private var secretKey: String = ""
    @State private var sessionToken: String = ""
    @State private var showAdvanced: Bool = false
    @State private var hasHydrated: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var isTesting: Bool = false
    @State private var testResult: TestResult?
    @State private var isRevealing: Bool = false
    @State private var revealError: String?
    @State private var secretsRevealed: Bool = false

    private enum TestResult: Equatable {
        case success
        case failure(String)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var existingAccount: S3Account? {
        if case .edit(let account) = mode { return account }
        return nil
    }

    private var isSaveDisabled: Bool {
        if isSaving { return true }
        let nameOK = !name.trimmingCharacters(in: .whitespaces).isEmpty
        // In edit mode, blank credentials are allowed and mean
        // "keep what's already in the Keychain". In create mode both
        // fields are still required.
        let credsOK: Bool
        if isEditing {
            credsOK = true
        } else {
            credsOK = !accessKey.trimmingCharacters(in: .whitespaces).isEmpty
                && !secretKey.isEmpty
        }
        let regionOK = !region.trimmingCharacters(in: .whitespaces).isEmpty
        let accountIDOK = !provider.requiresAccountID
            || !accountIdentifier.trimmingCharacters(in: .whitespaces).isEmpty
        let endpointOK = !provider.requiresEndpointOverride
            || Self.parseEndpoint(endpointOverride) != nil
        return !(nameOK && credsOK && regionOK && accountIDOK && endpointOK)
    }

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                credentialsSection
                advancedSection
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                if let testResult {
                    Section {
                        switch testResult {
                        case .success:
                            Label("account.test.success", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        case .failure(let message):
                            Label(message, systemImage: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "account.edit" : "account.add")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                        .disabled(isSaving)
                }
                if onTest != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("account.action.testConnection") { testConnection() }
                            .disabled(isSaveDisabled || isTesting)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { commit() }
                        .disabled(isSaveDisabled)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .overlay {
                if isSaving || isRevealing {
                    ProgressView()
                        .controlSize(.large)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .onAppear(perform: hydrate)
        }
        .frame(minWidth: 520, minHeight: 600)
    }

    // MARK: - Sections

    @ViewBuilder
    private var connectionSection: some View {
        Section("account.section.connection") {
            TextField("account.field.name", text: $name)
                .textContentType(.nickname)

            Picker("account.field.provider", selection: $provider) {
                ForEach(S3Provider.allCases, id: \.self) { p in
                    Label {
                        Text(p.displayName)
                    } icon: {
                        Image(systemName: p.iconSystemName)
                    }
                    .tag(p)
                }
            }
            .onChange(of: provider) { _, newValue in
                guard hasHydrated else { return }
                applyProviderDefaults(for: newValue)
            }

            if let regions = provider.fixedRegions {
                Picker("account.field.region", selection: $region) {
                    ForEach(regions, id: \.self) { Text($0).tag($0) }
                }
            } else {
                TextField("account.field.region", text: $region)
            }

            if provider.requiresAccountID {
                TextField("account.field.accountID", text: $accountIdentifier)
                    .textContentType(.username)
            }

            if provider.requiresEndpointOverride {
                TextField("account.field.endpoint", text: $endpointOverride)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
            }
        }
    }

    @ViewBuilder
    private var credentialsSection: some View {
        Section("account.section.credentials") {
            TextField("account.field.accessKey", text: $accessKey)
                .textContentType(.username)
                .autocorrectionDisabled()
            SecureField("account.field.secretKey", text: $secretKey)
                .textContentType(.password)

            if isEditing && !secretsRevealed && onLoadCredentials != nil {
                Button {
                    Task { await revealStoredCredentials() }
                } label: {
                    Label("account.action.revealStoredCredentials",
                          systemImage: "touchid")
                }
                .disabled(isRevealing)
            }

            if isEditing && !secretsRevealed {
                Text("account.note.credentialsKept")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if isEditing && secretsRevealed {
                Text("account.note.credentialsRevealed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let revealError {
                Label(revealError, systemImage: "lock.trianglebadge.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showAdvanced) {
                SecureField("account.field.sessionToken", text: $sessionToken)
                TextField("account.field.defaultBucket", text: $defaultBucket)
                    .autocorrectionDisabled()
                if provider.supportsPathStyleToggle {
                    Toggle("account.field.usePathStyle", isOn: $usesPathStyle)
                }
            } label: {
                Text("account.section.advanced")
            }
        }
    }

    // MARK: - Behaviour

    private func applyProviderDefaults(for newProvider: S3Provider) {
        if let fixed = newProvider.fixedRegions {
            if !fixed.contains(region) {
                region = newProvider.defaultRegion
            }
        } else {
            region = newProvider.defaultRegion
        }
        usesPathStyle = newProvider.usesPathStyleByDefault
    }

    private func hydrate() {
        defer { hasHydrated = true }
        if case .edit(let account) = mode {
            name = account.name
            provider = account.provider
            region = account.region
            endpointOverride = account.endpointOverride?.absoluteString ?? ""
            accountIdentifier = account.accountID ?? ""
            defaultBucket = account.defaultBucket ?? ""
            usesPathStyle = account.usesPathStyle
            // Non-secret fields above are restored as expected. Secret
            // material (access key, secret key, session token) is left
            // blank — the user authenticates via Touch ID / password
            // (see `revealStoredCredentials`) to fill them, or leaves
            // them blank and the Keychain values are preserved on save.
        } else {
            region = provider.defaultRegion
            usesPathStyle = provider.usesPathStyleByDefault
        }
    }

    /// Authenticates the user via LocalAuthentication and, on success,
    /// loads the existing credentials into the form fields. If the
    /// device has no biometrics and no password set, the lookup runs
    /// straight away.
    private func revealStoredCredentials() async {
        guard let existing = existingAccount,
              let onLoadCredentials else { return }
        isRevealing = true
        revealError = nil
        defer { isRevealing = false }

        let context = LAContext()
        context.localizedFallbackTitle = String(
            localized: "account.action.revealSecret.fallback",
            defaultValue: "Use Password"
        )
        var laError: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &laError) {
            do {
                try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: String(
                        localized: "account.action.revealSecret.reason",
                        defaultValue: "Reveal the stored secret access key"
                    )
                )
            } catch let error as LAError where error.code == .userCancel
                                              || error.code == .systemCancel
                                              || error.code == .appCancel {
                return
            } catch {
                revealError = error.localizedDescription
                return
            }
        }

        guard let credentials = await onLoadCredentials(existing.id) else {
            revealError = String(
                localized: "account.action.revealSecret.notFound",
                defaultValue: "No stored credentials were found for this account."
            )
            return
        }
        accessKey = credentials.accessKey
        secretKey = credentials.secretKey
        sessionToken = credentials.sessionToken ?? ""
        secretsRevealed = true
    }

    private func testConnection() {
        guard let onTest else { return }
        let (account, credentials) = buildPayload()
        testResult = nil
        isTesting = true
        Task {
            let result = await onTest(account, credentials)
            if let result {
                testResult = .failure(
                    result.errorDescription
                    ?? String(localized: "error.unknown",
                              defaultValue: "Unexpected error.")
                )
            } else {
                testResult = .success
            }
            isTesting = false
        }
    }

    private func buildPayload() -> (S3Account, AccountCredentials) {
        let trimmedEndpoint = endpointOverride.trimmingCharacters(in: .whitespaces)
        let endpoint: URL? = provider.requiresEndpointOverride
            ? Self.parseEndpoint(trimmedEndpoint)
            : nil
        let cleanedAccountID: String? = provider.requiresAccountID
            ? accountIdentifier.trimmingCharacters(in: .whitespaces)
            : nil
        let account = S3Account(
            id: existingAccount?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            provider: provider,
            region: region.trimmingCharacters(in: .whitespaces),
            endpointOverride: endpoint,
            accountID: cleanedAccountID,
            defaultBucket: defaultBucket.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            usesPathStyle: usesPathStyle,
            lastUsedAt: existingAccount?.lastUsedAt
        )
        let credentials = AccountCredentials(
            accessKey: accessKey.trimmingCharacters(in: .whitespaces),
            secretKey: secretKey,
            sessionToken: sessionToken.isEmpty ? nil : sessionToken
        )
        return (account, credentials)
    }

    private func performSave() {
        let (account, credentials) = buildPayload()
        isSaving = true
        saveError = nil
        Task {
            if let failure = await onSave(account, credentials) {
                saveError = failure.errorDescription
                    ?? String(localized: "error.unknown",
                              defaultValue: "Unexpected error.")
                isSaving = false
            } else {
                dismiss()
            }
        }
    }

    private func commit() { performSave() }

    /// Returns a valid HTTP/HTTPS URL with a non-empty host, or nil.
    static func parseEndpoint(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(percentEncoded: false),
              !host.isEmpty
        else { return nil }
        return url
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
