//
//  AccountListViewModel.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation
import BucketeerCore

@MainActor
@Observable
final class AccountListViewModel {
    var accounts: [S3Account] = []
    var error: BucketeerError?

    private let accountStore: any AccountStoring
    private let keychainStore: any KeychainStoring
    private let clientFactory: S3ClientFactory
    private let azureCredentialsCache: AzureCredentialsCache
    private let transferManager: TransferManager
    private let activityLog: (any ActivityLogging)?
    /// Phase 14 / Codex R2 (low) follow-up: hand the indexer to the
    /// view model so account-delete purges the right sub-domain
    /// instead of nuking the whole Bucketeer Spotlight index.
    var spotlightIndexer: SpotlightIndexer?

    init(
        accountStore: any AccountStoring,
        keychainStore: any KeychainStoring,
        clientFactory: S3ClientFactory,
        azureCredentialsCache: AzureCredentialsCache,
        transferManager: TransferManager,
        activityLog: (any ActivityLogging)? = nil
    ) {
        self.accountStore = accountStore
        self.keychainStore = keychainStore
        self.clientFactory = clientFactory
        self.azureCredentialsCache = azureCredentialsCache
        self.transferManager = transferManager
        self.activityLog = activityLog
    }

    /// Flush both credential caches so a deleted or edited account does
    /// not leak signing material into subsequent requests. The Azure cache
    /// is per-process-only — no AWSClient shutdown is required, but the
    /// signer must be re-derived from the (possibly rotated) Keychain
    /// value on the next request.
    private func invalidateAllCaches(for accountID: UUID) async {
        await clientFactory.invalidate(accountID: accountID)
        await azureCredentialsCache.invalidate(accountID: accountID)
    }

    func refresh() async {
        do {
            accounts = try await accountStore.all()
        } catch let error as BucketeerError {
            self.error = error
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
    }

    /// Loads the stored credentials for an account from the Keychain.
    /// Returns nil on failure. Used by the edit sheet to populate the
    /// secret fields after the user authenticates via Touch ID.
    func loadCredentials(for accountID: UUID) async -> AccountCredentials? {
        try? await keychainStore.load(for: accountID)
    }

    /// Saves the account in Keychain first, then in the SwiftData store.
    /// If the SwiftData write fails the rollback strategy depends on
    /// whether this is an edit or a create — Codex high #7: on edit
    /// we used to delete the original credentials too, which destroyed
    /// the user's existing access when only the metadata write failed.
    ///
    /// When the supplied `credentials` has an empty `secretKey`, the
    /// existing Keychain entry is left untouched and any non-empty
    /// fields from `credentials` are merged on top. This is the edit
    /// path where the user changes only metadata without re-entering
    /// the secret.
    @discardableResult
    func save(account: S3Account, credentials: AccountCredentials) async -> BucketeerError? {
        // Snapshot any existing credentials *before* the new save so
        // we can restore them if the SwiftData write fails on an edit.
        // "No item stored" (authenticationFailed from errSecItemNotFound)
        // legitimately means create; any OTHER Keychain failure must
        // abort — treating a transient error as "create" would make a
        // later rollback DELETE the user's real credentials, and the
        // merge below would overwrite them with an empty secret.
        let previousCredentials: AccountCredentials?
        do {
            previousCredentials = try await keychainStore.load(for: account.id)
        } catch BucketeerError.authenticationFailed {
            previousCredentials = nil
        } catch let error as BucketeerError {
            self.error = error
            return error
        } catch {
            let wrapped = BucketeerError.unknown(message: error.localizedDescription)
            self.error = wrapped
            return wrapped
        }
        let isEdit = previousCredentials != nil
        let effective = Self.mergeCredentials(
            existing: previousCredentials,
            form: credentials
        )

        do {
            try await keychainStore.save(effective, for: account.id)
        } catch let error as BucketeerError {
            self.error = error
            return error
        } catch {
            let wrapped = BucketeerError.unknown(message: error.localizedDescription)
            self.error = wrapped
            return wrapped
        }

        do {
            try await accountStore.upsert(account)
        } catch let error as BucketeerError {
            await rollbackCredentials(
                for: account.id,
                previous: previousCredentials,
                isEdit: isEdit
            )
            self.error = error
            return error
        } catch {
            await rollbackCredentials(
                for: account.id,
                previous: previousCredentials,
                isEdit: isEdit
            )
            let wrapped = BucketeerError.unknown(message: error.localizedDescription)
            self.error = wrapped
            return wrapped
        }

        // Credentials may have changed — drop any cached AWSClient that
        // still holds the old signing material.
        await invalidateAllCaches(for: account.id)
        await refresh()
        await record(
            isEdit ? .accountUpdated : .accountAdded,
            status: .info,
            account: account
        )
        return nil
    }

    /// Restore the pre-save credentials on a partial-failure rollback.
    /// - For an **edit**: rewrite the previous credentials so the
    ///   account stays usable.
    /// - For a **create**: delete the orphaned entry so we don't leave
    ///   junk in the Keychain for an account that never made it into
    ///   the SwiftData store.
    private func rollbackCredentials(
        for accountID: UUID,
        previous: AccountCredentials?,
        isEdit: Bool
    ) async {
        if isEdit, let previous {
            try? await keychainStore.save(previous, for: accountID)
        } else {
            try? await keychainStore.delete(for: accountID)
        }
    }

    /// Removes the account record first so the UI never shows an entry
    /// that has no working credentials; then removes the credential.
    /// A Keychain failure is logged via `error` but does not undo the
    /// account delete — orphan credentials are harmless without an
    /// account record referencing them and are cleaned up on next save.
    @discardableResult
    func delete(account: S3Account) async -> BucketeerError? {
        // Cancel any in-flight transfers for this account so workers
        // don't try to use the AWSClient we're about to shut down.
        await transferManager.cancelAll(for: account.id)

        do {
            try await accountStore.delete(id: account.id)
        } catch let error as BucketeerError {
            self.error = error
            return error
        } catch {
            let wrapped = BucketeerError.unknown(message: error.localizedDescription)
            self.error = wrapped
            return wrapped
        }

        do {
            try await keychainStore.delete(for: account.id)
        } catch let error as BucketeerError {
            self.error = error
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }

        await invalidateAllCaches(for: account.id)
        // Codex audit R2 (low) follow-up: targeted Spotlight purge.
        // Other accounts' search results stay intact.
        if let spotlightIndexer {
            await spotlightIndexer.purgeAccount(account.id)
        }
        await refresh()
        await record(.accountDeleted, status: .info, account: account)
        return nil
    }

    // MARK: - Audit log

    private func record(
        _ kind: ActivityKind,
        status: ActivityStatus,
        account: S3Account
    ) async {
        guard let activityLog else { return }
        await activityLog.record(
            ActivityEntry(
                kind: kind,
                status: status,
                accountID: account.id,
                accountName: account.name
            )
        )
    }

    /// Validates the supplied account configuration and credentials by
    /// issuing a lightweight `ListBuckets` call. The throwaway client
    /// is shut down before the call returns; nothing is persisted. Use
    /// this from the Add/Edit Account sheet to verify a connection
    /// before the user commits. Empty fields fall back to the stored
    /// credentials, so a Test from the edit sheet works without
    /// re-entering the secret.
    func testConnection(
        account: S3Account,
        credentials: AccountCredentials
    ) async -> BucketeerError? {
        // Same not-found vs transient-error distinction as save():
        // a Keychain hiccup must surface, not silently degrade the
        // test into "use the blank form secret".
        let existing: AccountCredentials?
        do {
            existing = try await keychainStore.load(for: account.id)
        } catch BucketeerError.authenticationFailed {
            existing = nil
        } catch let error as BucketeerError {
            return error
        } catch {
            return .unknown(message: error.localizedDescription)
        }
        let effective = Self.mergeCredentials(existing: existing, form: credentials)
        do {
            switch account.provider.family {
            case .s3:
                try await S3ClientFactory.testConnection(
                    for: account,
                    credentials: effective
                )
            case .azureBlob:
                try await AzureBlobObjectStore.testConnection(
                    account: account,
                    credentials: effective
                )
            }
            return nil
        } catch let error as BucketeerError {
            return error
        } catch {
            return .unknown(message: error.localizedDescription)
        }
    }

    /// Merge the form-supplied credentials over the stored copy. Any
    /// blank field falls back to the stored value, so users can edit
    /// metadata without re-typing the secret. With no stored entry
    /// (create mode), the form value is used verbatim.
    ///
    /// Pure function over the snapshot `save()` already loaded — the
    /// old version re-read the Keychain with `try?`, so a transient
    /// Keychain error silently degraded an edit into "use the blank
    /// form secret" and overwrote valid credentials.
    static func mergeCredentials(
        existing: AccountCredentials?,
        form: AccountCredentials
    ) -> AccountCredentials {
        guard let existing else { return form }
        return AccountCredentials(
            accessKey: form.accessKey.isEmpty ? existing.accessKey : form.accessKey,
            secretKey: form.secretKey.isEmpty ? existing.secretKey : form.secretKey,
            sessionToken: form.sessionToken ?? existing.sessionToken
        )
    }
}
