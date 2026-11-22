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
        let clean = BackupMemoryStore()
        let entries = try KeyBackupService.open(backup, passphrase: passphrase)
        let plan = try await clean.importPlan(entries, knownAccountIDs: [])
        #expect(plan.first?.state == .unknownAccount)
        try await clean.importKey(entries[0], replacing: nil)
        let restored = try #require(try await clean.key(accountID: key.accountID, bucket: key.bucket))
        let restoredBytes = try await clean.keyMaterial(id: restored.id)
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
        let conflict = KeyBackupEntry(id: original.id, accountID: original.accountID, accountDisplayName: nil, bucket: original.bucket, label: original.label, rawKey: Data(repeating: 7, count: 32), createdAt: original.createdAt)
        let fresh = entry()
        let orphan = entry()
        let plan = try await store.importPlan([original, conflict, fresh, orphan], knownAccountIDs: [original.accountID, fresh.accountID])
        #expect(plan.map(\.state) == [.identical, .conflict, .new, .unknownAccount])
        await #expect(throws: KeyBackupError.staleConflict) { try await store.importKey(conflict, replacing: nil) }
        let stored = try #require(try await store.key(accountID: original.accountID, bucket: original.bucket))
        #expect(try await store.keyMaterial(id: stored.id) == original.rawKey)
        try await store.importKey(conflict, replacing: stored.id)
        let replaced = try #require(try await store.key(accountID: original.accountID, bucket: original.bucket))
        #expect(try await store.keyMaterial(id: replaced.id) == conflict.rawKey)
        // The formerly identical plan must not overwrite a replacement or
        // silently succeed after its local key has been removed.
        await #expect(throws: KeyBackupError.staleConflict) {
            try await store.importKey(original, replacing: plan[0].existingID)
        }
        try await store.delete(id: replaced.id)
        await #expect(throws: KeyBackupError.staleConflict) {
            try await store.importKey(original, replacing: plan[0].existingID)
        }
    }

    @Test("Missing Keychain bytes can be restored without deleting metadata")
    func missingMaterial() async throws {
        let store = BackupMemoryStore()
        let original = entry()
        try await store.importKey(original, replacing: nil)
        let stored = try #require(try await store.key(accountID: original.accountID, bucket: original.bucket))
        await store.removeMaterial(id: stored.id)
        let plan = try await store.importPlan([original], knownAccountIDs: [original.accountID])
        #expect(plan.first?.state == .missingLocal)
        #expect(plan.first?.existingID == stored.id)
        try await store.importKey(original, replacing: stored.id)
        let restored = try #require(try await store.key(accountID: original.accountID, bucket: original.bucket))
        #expect(try await store.keyMaterial(id: restored.id) == original.rawKey)
    }

    @Test("Canonically equivalent passphrases open the same backup")
    func normalizedPassphrase() throws {
        let composed = "caf\u{e9} recovery words"
        let decomposed = "cafe\u{301} recovery words"
        let backup = try KeyBackupService.seal([entry()], passphrase: composed, confirmation: decomposed)
        #expect(try KeyBackupService.open(backup, passphrase: decomposed).count == 1)
    }

    @Test("Backup entries and plans redact key material from diagnostics")
    func redactedDiagnostics() async throws {
        let original = entry()
        let plan = try await BackupMemoryStore().importPlan([original], knownAccountIDs: [])
        for value: Any in [original, plan[0]] {
            var output = ""
            dump(value, to: &output)
            #expect(output.contains("<redacted>"))
            #expect(!output.contains("32 bytes"))
            #expect(String(reflecting: value).contains("<redacted>"))
            #expect(Mirror(reflecting: value).children.allSatisfy { $0.value is String })
        }
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
    func removeMaterial(id: UUID) { material.removeValue(forKey: id) }
    func delete(id: UUID) {
        metadata.removeAll { $0.id == id }
        material.removeValue(forKey: id)
    }
    func copyForReassignment(_ key: BucketEncryptionKey, to accountID: UUID) throws -> BucketEncryptionKey {
        throw EncryptionKeyReassignmentError.conflict
    }
    func importKey(_ entry: KeyBackupEntry, replacing expectedID: UUID?) throws {
        let existing = key(accountID: entry.accountID, bucket: entry.bucket)
        guard try KeyBackupService.shouldImport(entry, existing: existing, existingBytes: existing.flatMap { material[$0.id] }, replacing: expectedID) else { return }
        if let existing { delete(id: existing.id) }
        let key = BucketEncryptionKey(label: entry.label, accountID: entry.accountID, bucket: entry.bucket, createdAt: entry.createdAt)
        metadata.append(key)
        material[key.id] = entry.rawKey
    }
    func markBackupReady(id: UUID) {}
}
