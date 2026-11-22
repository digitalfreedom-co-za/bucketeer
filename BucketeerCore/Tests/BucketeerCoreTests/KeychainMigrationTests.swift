//
//  KeychainMigrationTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 22.11.26.
//

import Foundation
import Security
import Testing
@testable import BucketeerCore

/// The launch migration must only ever see and delete items in the
/// file-based keychain. Query shape only; no Keychain.
@Suite("Keychain migration")
struct KeychainMigrationTests {

    @Test("The legacy listing and delete are scoped to the file-based keychain and never match the shared item")
    func legacyQueriesNeverReachTheSharedItem() {
        let list = KeychainStore.legacyListQuery(service: "za.co.digitalfreedom.bucketeer")
        let ref = Data([1, 2, 3])
        let delete = KeychainStore.legacyDeleteQuery(persistentRef: ref)

        // Omitting the key also matches the data-protection keychain (#66).
        #expect(list[kSecUseDataProtectionKeychain as String] as? Bool == false)
        #expect(delete[kSecUseDataProtectionKeychain as String] as? Bool == false)
        #expect(list[kSecReturnPersistentRef as String] as? Bool == true)
        // The delete targets the listed item, not every item for the account.
        #expect(delete[kSecValuePersistentRef as String] as? Data == ref)
        #expect(delete[kSecAttrAccount as String] == nil)
        #expect(delete[kSecAttrAccessGroup as String] == nil)
    }
}
