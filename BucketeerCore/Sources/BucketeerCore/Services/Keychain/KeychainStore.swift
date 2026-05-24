//
//  KeychainStore.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation
import Security

/// Keychain-backed implementation of `KeychainStoring`. One generic
/// password item per account, keyed by `kSecAttrAccount = accountID`.
/// Items live in the shared access group so the File Provider extension
/// can read the same credentials.
public actor KeychainStore: KeychainStoring {
    private let service: String
    private let accessGroup: String?

    public init(service: String, accessGroup: String?) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - KeychainStoring

    public func save(_ credentials: AccountCredentials, for accountID: UUID) async throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(credentials)
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }

        let identityQuery = baseQuery(for: accountID)

        let updateStatus = SecItemUpdate(
            identityQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = identityQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            addQuery[kSecAttrSynchronizable as String] = false
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw BucketeerError.keychainFailure(status: addStatus)
            }
        default:
            throw BucketeerError.keychainFailure(status: updateStatus)
        }
    }

    public func load(for accountID: UUID) async throws -> AccountCredentials {
        var query = baseQuery(for: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw BucketeerError.authenticationFailed
            }
            throw BucketeerError.keychainFailure(status: status)
        }
        guard let data = result as? Data else {
            throw BucketeerError.keychainFailure(status: errSecItemNotFound)
        }
        do {
            return try JSONDecoder().decode(AccountCredentials.self, from: data)
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }

    public func delete(for accountID: UUID) async throws {
        let status = SecItemDelete(baseQuery(for: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BucketeerError.keychainFailure(status: status)
        }
    }

    // MARK: - Migration

    /// One-shot migration from the legacy private-namespace Keychain
    /// items (created when the host had `accessGroup: nil`) to the
    /// shared access group used by both host and File Provider
    /// extension. Codex blocker #3 — without this migration, every
    /// existing account stops working the moment the host starts
    /// writing to the shared group.
    ///
    /// Algorithm: for each item in the private namespace with our
    /// service identifier, copy the payload into the shared group, then
    /// delete the legacy entry. Items already in the shared group are
    /// left untouched. Idempotent — re-running is a no-op once the
    /// private namespace is empty.
    public func migrateFromLegacyPrivateNamespace() async {
        // Only meaningful if we're configured against a shared access
        // group in the first place — otherwise there is nothing to
        // migrate to.
        guard accessGroup != nil else { return }

        // List every generic-password item in the private namespace
        // (no kSecAttrAccessGroup) for our service.
        let listQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(listQuery as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return }

        for item in items {
            guard let accountString = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data,
                  let accountID = UUID(uuidString: accountString)
            else { continue }
            // If the shared-group entry already exists, skip — we don't
            // want to overwrite a credential the user updated in a
            // signed build with an older private-namespace copy.
            if (try? await load(for: accountID)) != nil { continue }
            do {
                let credentials = try JSONDecoder().decode(AccountCredentials.self, from: data)
                try await save(credentials, for: accountID)
                // Best-effort: delete the legacy entry once the shared
                // copy is in place. A failure here is non-fatal — the
                // user's credentials are safe in the shared group and
                // the next migration run will pick up the stragglers.
                let deleteQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: accountString
                ]
                _ = SecItemDelete(deleteQuery as CFDictionary)
            } catch {
                continue
            }
        }
    }

    // MARK: - Internals

    private func baseQuery(for accountID: UUID) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
