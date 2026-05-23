//
//  AccountListViewModel.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation

@MainActor
@Observable
final class AccountListViewModel {
    var accounts: [S3Account] = []
    var error: S3BrowserError?

    private let accountStore: AccountStoring
    private let keychainStore: KeychainStoring
    private let clientFactory: S3ClientFactory
    private let transferManager: TransferManager

    init(
        accountStore: AccountStoring,
        keychainStore: KeychainStoring,
        clientFactory: S3ClientFactory,
        transferManager: TransferManager
    ) {
        self.accountStore = accountStore
        self.keychainStore = keychainStore
        self.clientFactory = clientFactory
        self.transferManager = transferManager
    }

    func refresh() async {
        do {
            accounts = try await accountStore.all()
        } catch let error as S3BrowserError {
            self.error = error
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
    }

    /// Saves the account in Keychain first, then in the SwiftData store.
    /// If the SwiftData write fails the Keychain entry is rolled back so
    /// neither store retains an orphaned record. Returns the error so
    /// the calling sheet can keep itself open and surface a message.
    @discardableResult
    func save(account: S3Account, credentials: AccountCredentials) async -> S3BrowserError? {
        do {
            try await keychainStore.save(credentials, for: account.id)
        } catch let error as S3BrowserError {
            self.error = error
            return error
        } catch {
            let wrapped = S3BrowserError.unknown(message: error.localizedDescription)
            self.error = wrapped
            return wrapped
        }

        do {
            try await accountStore.upsert(account)
        } catch let error as S3BrowserError {
            // SwiftData failed after Keychain succeeded — roll back the
            // credential so we never have orphans in the Keychain.
            try? await keychainStore.delete(for: account.id)
            self.error = error
            return error
        } catch {
            try? await keychainStore.delete(for: account.id)
            let wrapped = S3BrowserError.unknown(message: error.localizedDescription)
            self.error = wrapped
            return wrapped
        }

        // Credentials may have changed — drop any cached AWSClient that
        // still holds the old signing material.
        await clientFactory.invalidate(accountID: account.id)
        await refresh()
        return nil
    }

    /// Removes the account record first so the UI never shows an entry
    /// that has no working credentials; then removes the credential.
    /// A Keychain failure is logged via `error` but does not undo the
    /// account delete — orphan credentials are harmless without an
    /// account record referencing them and are cleaned up on next save.
    @discardableResult
    func delete(account: S3Account) async -> S3BrowserError? {
        // Cancel any in-flight transfers for this account so workers
        // don't try to use the AWSClient we're about to shut down.
        await transferManager.cancelAll(for: account.id)

        do {
            try await accountStore.delete(id: account.id)
        } catch let error as S3BrowserError {
            self.error = error
            return error
        } catch {
            let wrapped = S3BrowserError.unknown(message: error.localizedDescription)
            self.error = wrapped
            return wrapped
        }

        do {
            try await keychainStore.delete(for: account.id)
        } catch let error as S3BrowserError {
            self.error = error
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }

        await clientFactory.invalidate(accountID: account.id)
        await refresh()
        return nil
    }
}
