//
//  InMemoryKeychain.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

#if DEBUG
import Foundation
import BucketeerCore

/// `KeychainStoring` without the Keychain — tests and the screenshot
/// demo mode never read or write real credentials.
actor InMemoryKeychain: KeychainStoring {
    private var items: [UUID: AccountCredentials] = [:]

    func save(_ credentials: AccountCredentials, for accountID: UUID) async throws {
        items[accountID] = credentials
    }

    func load(for accountID: UUID) async throws -> AccountCredentials {
        guard let credentials = items[accountID] else { throw BucketeerError.authenticationFailed }
        return credentials
    }

    func delete(for accountID: UUID) async throws {
        items[accountID] = nil
    }
}
#endif
