import CryptoKit
import Foundation
import Testing
@testable import BucketeerCore

@Suite("Encrypted key backups")
struct KeyBackupTests {
    private let passphrase = "several unrelated words for recovery"

    @Test("Backup restores the key needed by an existing BCKT object")
    func roundTrip() async throws {
        let store = BackupMemoryStore()
        let key = try await store.create(label: "Archive", accountID: UUID(), bucket: "archive")
        let bytes = try await store.keyMaterial(id: key.id)
        let object = try BucketeerEnvelope.seal(plaintext: Data("precious object".utf8), key: SymmetricKey(data: bytes))
        let backup = try await store.exportKeys(ids: [key.id], accountNames: [:], passphrase: passphrase, confirmation: passphrase)
        try await store.delete(id: key.id)
        let entries = try KeyBackupService.open(backup, passphrase: passphrase)
        let plan = try await store.importPlan(entries, knownAccountIDs: [])
        #expect(plan.first?.state == .unknownAccount)
        try await store.importKey(entries[0], replacing: nil)
        let restored = try #require(try await store.key(accountID: key.accountID, bucket: key.bucket))
        let restoredBytes = try await store.keyMaterial(id: restored.id)
        #expect(try BucketeerEnvelope.open(envelope: object, key: SymmetricKey(data: restoredBytes)) == Data("precious object".utf8))
    }

    @Test("Wrong passphrase authenticates no entries")
    func wrongPassphrase() throws {
        let backup = try KeyBackupService.seal([entry()], passphrase: passphrase, confirmation: passphrase)
        #expect(throws: KeyBackupError.authenticationFailed) {
            try KeyBackupService.open(backup, passphrase: "another unrelated passphrase")
        }
    }

    @Test("Tampered ciphertext and authenticated header fail closed")
    func tampering() throws {
        let backup = try KeyBackupService.seal([entry()], passphrase: passphrase, confirmation: passphrase)
        for offset in [13, 29, 41, backup.count - 1] {
            var changed = backup
            changed[offset] ^= 1
            #expect(throws: KeyBackupError.authenticationFailed) {
                try KeyBackupService.open(changed, passphrase: passphrase)
            }
        }
    }

    @Test("Plans distinguish identical, conflicting, new and orphaned keys; conflicts default to keep")
    func conflicts() async throws {
        let store = BackupMemoryStore()
        let original = entry()
        try await store.importKey(original, replacing: nil)
        var conflict = original
        conflict.rawKey = Data(repeating: 7, count: 32)
        let fresh = entry()
        let orphan = entry()
        let plan = try await store.importPlan([original, conflict, fresh, orphan], knownAccountIDs: [original.accountID, fresh.accountID])
        #expect(plan.map(\.state) == [.identical, .conflict, .new, .unknownAccount])
        try await store.importKey(conflict, replacing: nil)
        let stored = try #require(try await store.key(accountID: original.accountID, bucket: original.bucket))
        #expect(try await store.keyMaterial(id: stored.id) == original.rawKey)
        try await store.importKey(conflict, replacing: stored.id)
        let replaced = try #require(try await store.key(accountID: original.accountID, bucket: original.bucket))
        #expect(try await store.keyMaterial(id: replaced.id) == conflict.rawKey)
    }

    private func entry() -> KeyBackupEntry {
        KeyBackupEntry(id: UUID(), accountID: UUID(), accountDisplayName: nil, bucket: "archive", label: "Archive", rawKey: Data(repeating: 42, count: 32), createdAt: Date())
    }
}

private actor BackupMemoryStore: EncryptionKeyStoring {
    var metadata: [BucketEncryptionKey] = []
    var material: [UUID: Data] = [:]
    func all() -> [BucketEncryptionKey] { metadata }
    func key(accountID: UUID, bucket: String) -> BucketEncryptionKey? {
        metadata.first { $0.accountID == accountID && $0.bucket == bucket }
    }
    func keyMaterial(id: UUID) throws -> Data {
        guard let bytes = material[id] else { throw EncryptionError.keyRemoved }
        return bytes
    }
    func create(label: String, accountID: UUID, bucket: String) -> BucketEncryptionKey {
        let key = BucketEncryptionKey(label: label, accountID: accountID, bucket: bucket)
        metadata.append(key)
        material[key.id] = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        return key
    }
    func delete(id: UUID) {
        metadata.removeAll { $0.id == id }
        material.removeValue(forKey: id)
    }
    func copyForReassignment(_ key: BucketEncryptionKey, to accountID: UUID) throws -> BucketEncryptionKey {
        throw EncryptionKeyReassignmentError.conflict
    }
    func importKey(_ entry: KeyBackupEntry, replacing expectedID: UUID?) throws {
        let existing = key(accountID: entry.accountID, bucket: entry.bucket)
        guard try KeyBackupService.shouldImport(entry, existing: existing, existingBytes: existing.map { try keyMaterial(id: $0.id) }, replacing: expectedID) else { return }
        if let existing { delete(id: existing.id) }
        let key = BucketEncryptionKey(label: entry.label, accountID: entry.accountID, bucket: entry.bucket, createdAt: entry.createdAt)
        metadata.append(key)
        material[key.id] = entry.rawKey
    }
    func markBackupReady(id: UUID) {}
}
