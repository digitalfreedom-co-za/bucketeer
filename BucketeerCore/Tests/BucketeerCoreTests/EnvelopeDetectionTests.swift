import CryptoKit
import Foundation
import Testing
@testable import BucketeerCore

@Suite("Envelope detection")
struct EnvelopeDetectionTests {
    @Test("Marked envelopes decrypt, and malformed or unauthentic marked objects fail closed")
    func marked() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("payload".utf8)
        let sealed = try BucketeerEnvelope.seal(plaintext: plain, key: key)
        #expect(try BucketeerEnvelope.decryptedPayload(sealed, marked: true, key: key) == plain)
        #expect(throws: EncryptionError.authenticationFailed) {
            try BucketeerEnvelope.decryptedPayload(sealed, marked: true, key: SymmetricKey(size: .bits256))
        }
        #expect(throws: EncryptionError.badEnvelope) {
            try BucketeerEnvelope.decryptedPayload(Data("BCKT".utf8), marked: true, key: key)
        }
        #expect(throws: EncryptionError.badEnvelope) {
            try BucketeerEnvelope.decryptedPayload(plain, marked: true, key: key)
        }
    }

    @Test("Legacy envelopes authenticate; structurally invalid headers pass through")
    func legacy() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("payload".utf8)
        var sealed = try BucketeerEnvelope.seal(plaintext: plain, key: key)
        #expect(try BucketeerEnvelope.decryptedPayload(sealed, marked: false, key: key) == plain)
        #expect(try BucketeerEnvelope.decryptedPayload(Data("BCKT plain text".utf8), marked: false, key: key) == nil)
        var unsupported = sealed
        unsupported[4] = 99
        #expect(try BucketeerEnvelope.decryptedPayload(unsupported, marked: false, key: key) == nil)
        sealed[sealed.count - 1] ^= 1
        #expect(throws: EncryptionError.authenticationFailed) {
            try BucketeerEnvelope.decryptedPayload(sealed, marked: false, key: key)
        }
        var reserved = try BucketeerEnvelope.seal(plaintext: plain, key: key)
        reserved[6] ^= 1
        #expect(throws: EncryptionError.authenticationFailed) {
            try BucketeerEnvelope.decryptedPayload(reserved, marked: false, key: key)
        }
    }

    @Test("Unmarked plaintext passes through in a keyed bucket")
    func plaintext() throws {
        #expect(try BucketeerEnvelope.decryptedPayload(Data("plain".utf8), marked: false,
                                                       key: SymmetricKey(size: .bits256)) == nil)
    }

    @Test("Marked objects without a key fail closed", arguments: [Data(), Data("BCKT plain".utf8)])
    func missingKey(data: Data) {
        #expect(throws: EncryptionError.noKeyForBucket) {
            try BucketeerEnvelope.decryptedPayload(data, marked: true, key: nil)
        }
    }

    @Test("Without a key all unmarked bytes pass through")
    func unkeyed() throws {
        let sealed = try BucketeerEnvelope.seal(plaintext: Data(), key: SymmetricKey(size: .bits256))
        for data in [Data(), Data("plain".utf8), Data("BCKT plain".utf8), sealed] {
            #expect(try BucketeerEnvelope.decryptedPayload(data, marked: false, key: nil) == nil)
        }
    }
    @Test("An unreadable staging file throws even without a bucket key")
    func unreadableStaging() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("missing")
        #expect(throws: (any Error).self) {
            try BucketeerEnvelope.finalizeDownload(at: missing, marked: false, key: nil)
        }
    }

}
