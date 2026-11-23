//
//  KeychainStore.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation
import os
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
            Self.logStatus("credential.save update", accountID, updateStatus)
        case errSecItemNotFound:
            var addQuery = identityQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            addQuery[kSecAttrSynchronizable as String] = false
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            Self.logStatus("credential.save add", accountID, addStatus)
            guard addStatus == errSecSuccess else {
                throw BucketeerError.keychainFailure(status: addStatus)
            }
        default:
            Self.logStatus("credential.save update", accountID, updateStatus)
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
            Self.logStatus("credential.load", accountID, status)
            throw Self.loadError(for: status)
        }
        guard let data = result as? Data else {
            Self.logStatus("credential.load noData", accountID, errSecItemNotFound)
            throw BucketeerError.keychainFailure(status: errSecItemNotFound)
        }
        do {
            return try JSONDecoder().decode(AccountCredentials.self, from: data)
        } catch {
            Self.logStatus("credential.load undecodable", accountID, errSecDecode)
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }

    public func delete(for accountID: UUID) async throws {
        let status = SecItemDelete(baseQuery(for: accountID) as CFDictionary)
        Self.logStatus("credential.delete", accountID, status)
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
    /// Every legacy query sets `kSecUseDataProtectionKeychain = false`
    /// explicitly: a query that merely omits the key is also matched
    /// against the data-protection keychain for an app with a
    /// keychain-access-groups entitlement, so the listing found the
    /// shared item itself and the account-wide delete then removed it
    /// on every launch (#66). The delete targets the listed item by
    /// persistent reference only, and runs only after the shared copy
    /// reads back as a different item; on any failure the legacy item
    /// stays in place and the next launch retries.
    public func migrateFromLegacyFileKeychain() async {
        guard accessGroup != nil else {
            CredentialLog.logger.info("migration.skip noAccessGroup")
            return
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(Self.legacyListQuery(service: service) as CFDictionary, &result)
        CredentialLog.logger.info("migration.list status=\(status, privacy: .public)")
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return }

        for item in items {
            guard let accountString = item[kSecAttrAccount as String] as? String,
                  let accountID = UUID(uuidString: accountString)
            else {
                CredentialLog.logger.error("migration.item noAccountID")
                continue
            }
            guard let legacyRef = item[kSecValuePersistentRef as String] as? Data else {
                Self.logStatus("migration.item noPersistentRef", accountID, errSecItemNotFound)
                continue
            }
            guard let data = Self.legacyData(persistentRef: legacyRef, accountID: accountID) else { continue }
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
            Self.logStatus("migration.copy", accountID, addStatus)
            guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else { continue }
            // `load` logs its own failure status.
            guard (try? await load(for: accountID)) != nil else { continue }
            Self.logStatus("migration.verify readBack", accountID, errSecSuccess)
            guard let sharedRef = sharedPersistentRef(for: accountID) else { continue }
            guard sharedRef != legacyRef else {
                CredentialLog.logger.error(
                    "migration.verify sameItem account=\(accountID.uuidString, privacy: .public), legacy item kept"
                )
                continue
            }
            let deleteStatus = SecItemDelete(Self.legacyDeleteQuery(persistentRef: legacyRef) as CFDictionary)
            Self.logStatus("migration.deleteLegacy", accountID, deleteStatus)
        }
    }

    /// Lists the file-based keychain only. Attributes and persistent
    /// references, no data: the file-based keychain rejects
    /// `kSecReturnData` together with `kSecMatchLimitAll`.
    static func legacyListQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: false,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnPersistentRef as String: true
        ]
    }

    /// Deletes exactly the one file-based item the listing returned —
    /// never by account name, which would also match the shared item.
    static func legacyDeleteQuery(persistentRef: Data) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: false,
            kSecValuePersistentRef as String: persistentRef
        ]
    }

    private static func legacyData(persistentRef: Data, accountID: UUID) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: false,
            kSecValuePersistentRef as String: persistentRef,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        logStatus("migration.readLegacy", accountID, status)
        guard status == errSecSuccess else { return nil }
        guard let data = result as? Data else {
            logStatus("migration.readLegacy noData", accountID, errSecItemNotFound)
            return nil
        }
        return data
    }

    private func sharedPersistentRef(for accountID: UUID) -> Data? {
        var query = baseQuery(for: accountID)
        query[kSecReturnPersistentRef as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        Self.logStatus("migration.verify sharedRef", accountID, status)
        guard status == errSecSuccess else { return nil }
        guard let ref = result as? Data else {
            Self.logStatus("migration.verify sharedRef noData", accountID, errSecItemNotFound)
            return nil
        }
        return ref
    }

    // MARK: - Internals

    private static func logStatus(_ event: String, _ accountID: UUID, _ status: OSStatus) {
        let level: OSLogType = status == errSecSuccess ? .info : .error
        CredentialLog.logger.log(
            level: level,
            "\(event, privacy: .public) account=\(accountID.uuidString, privacy: .public) status=\(status, privacy: .public)"
        )
    }

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
