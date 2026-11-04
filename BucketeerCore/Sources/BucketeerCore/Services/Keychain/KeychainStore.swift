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
            throw Self.loadError(for: status)
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

    /// One-shot migration of credentials from the file-based login
    /// keychain into the shared access group of the data-protection
    /// keychain, which both the host and the File Provider extension
    /// read. Earlier builds never set `kSecUseDataProtectionKeychain`,
    /// so every item they wrote — with or without an access-group
    /// attribute — lives in the file-based keychain, where macOS
    /// ignores access groups (SecItem.h).
    ///
    /// Queries without `kSecUseDataProtectionKeychain` (and without
    /// `kSecAttrSynchronizable`) only reach the file-based keychain, so
    /// the listing and the delete below never touch the shared items.
    /// A legacy item is deleted only after its shared copy reads back;
    /// on any failure it stays in place and the next launch retries.
    public func migrateFromLegacyFileKeychain() async {
        guard accessGroup != nil else { return }

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
                  let accountID = UUID(uuidString: accountString),
                  let data = item[kSecValueData as String] as? Data
            else { continue }
            // SecItemAdd (not update) so an existing shared entry, which
            // may be newer, is never overwritten.
            var addQuery = baseQuery(for: accountID)
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            addQuery[kSecAttrSynchronizable as String] = false
            if let creation = item[kSecAttrCreationDate as String] {
                addQuery[kSecAttrCreationDate as String] = creation
            }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem,
                  (try? await load(for: accountID)) != nil
            else { continue }
            let legacyDeleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: accountString
            ]
            _ = SecItemDelete(legacyDeleteQuery as CFDictionary)
        }
    }

    // MARK: - Internals

    /// A missing item is not a failed sign-in: the user has to enter
    /// the credentials again, the provider never saw a request.
    static func loadError(for status: OSStatus) -> BucketeerError {
        status == errSecItemNotFound
            ? .credentialsMissing
            : .keychainFailure(status: status)
    }

    /// With an access group the query targets the data-protection
    /// keychain: on macOS that is the only backend that honours
    /// `kSecAttrAccessGroup` for non-synchronizable items, and therefore
    /// the only way the extension sees the host's credentials. Signed
    /// builds only — unsigned ones get `errSecMissingEntitlement`.
    private func baseQuery(for accountID: UUID) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }
}
