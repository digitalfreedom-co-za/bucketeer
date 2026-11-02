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
    /// extension. Without it, existing accounts stop working the moment
    /// the host starts writing to the shared group.
    ///
    /// A query without `kSecAttrAccessGroup` searches *every* access
    /// group the app belongs to (SecItem.h), so the listing also returns
    /// the shared items and an unscoped delete would remove them too.
    /// Hence: shared-group items are skipped, and a legacy item is only
    /// deleted through a query scoped to its own reported access group.
    /// Items that report no group are left in place; re-running is then
    /// a harmless duplicate-add.
    public func migrateFromLegacyPrivateNamespace() async {
        guard let accessGroup else { return }

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
            let itemGroup = item[kSecAttrAccessGroup as String] as? String
            guard itemGroup != accessGroup,
                  let accountString = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data,
                  UUID(uuidString: accountString) != nil
            else { continue }
            // SecItemAdd (not update) so an existing shared entry, which
            // may be newer, is never overwritten.
            var addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: accountString,
                kSecAttrAccessGroup as String: accessGroup,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
                kSecAttrSynchronizable as String: false
            ]
            if let creation = item[kSecAttrCreationDate as String] {
                addQuery[kSecAttrCreationDate as String] = creation
            }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem,
                  let itemGroup
            else { continue }
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: accountString,
                kSecAttrAccessGroup as String: itemGroup
            ]
            _ = SecItemDelete(deleteQuery as CFDictionary)
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
