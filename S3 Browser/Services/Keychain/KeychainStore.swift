//
//  KeychainStore.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation
import Security

/// Keychain-backed implementation of `KeychainStoring`. One generic
/// password item per account, keyed by `kSecAttrAccount = accountID`.
/// Items live in the shared access group so the File Provider extension
/// can read the same credentials.
actor KeychainStore: KeychainStoring {
    private let service: String
    private let accessGroup: String?

    init(service: String, accessGroup: String?) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - KeychainStoring

    func save(_ credentials: AccountCredentials, for accountID: UUID) async throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(credentials)
        } catch {
            throw S3BrowserError.persistenceFailure(message: error.localizedDescription)
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
                throw S3BrowserError.keychainFailure(status: addStatus)
            }
        default:
            throw S3BrowserError.keychainFailure(status: updateStatus)
        }
    }

    func load(for accountID: UUID) async throws -> AccountCredentials {
        var query = baseQuery(for: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw S3BrowserError.authenticationFailed
            }
            throw S3BrowserError.keychainFailure(status: status)
        }
        guard let data = result as? Data else {
            throw S3BrowserError.keychainFailure(status: errSecItemNotFound)
        }
        do {
            return try JSONDecoder().decode(AccountCredentials.self, from: data)
        } catch {
            throw S3BrowserError.persistenceFailure(message: error.localizedDescription)
        }
    }

    func delete(for accountID: UUID) async throws {
        let status = SecItemDelete(baseQuery(for: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw S3BrowserError.keychainFailure(status: status)
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
