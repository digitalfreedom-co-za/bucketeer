//
//  BucketeerEnvelopeAADTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import CryptoKit
import Testing
@testable import BucketeerCore

/// Extra coverage for the AAD-authenticated envelope (Codex R1
/// medium #1). The original `BucketeerEnvelopeTests` covered the
/// header tamper paths; this suite probes a wider set of edge
/// cases that came up during the audit follow-ups.
@Suite("BucketeerEnvelope (AAD + edges)")
struct BucketeerEnvelopeAADTests {

    @Test("Two seals with the same plaintext + key produce different envelopes")
    func nonceVariesPerSeal() throws {
        let key = SymmetricKey(size: .bits256)
        let pt = Data("payload".utf8)
        let a = try BucketeerEnvelope.seal(plaintext: pt, key: key)
        let b = try BucketeerEnvelope.seal(plaintext: pt, key: key)
        #expect(a != b, "AES-GCM nonce should be fresh on every seal")
        // Both should still open cleanly.
        #expect(try BucketeerEnvelope.open(envelope: a, key: key) == pt)
        #expect(try BucketeerEnvelope.open(envelope: b, key: key) == pt)
    }

    @Test("A 1-byte truncation of the envelope fails open")
    func truncationDetected() throws {
        let key = SymmetricKey(size: .bits256)
        let env = try BucketeerEnvelope.seal(plaintext: Data("hi".utf8), key: key)
        let truncated = env.dropLast()
        do {
            _ = try BucketeerEnvelope.open(envelope: truncated, key: key)
            #expect(Bool(false), "truncated envelope should fail")
        } catch let error as EncryptionError {
            #expect(error == .authenticationFailed || error == .badEnvelope)
        }
    }

    @Test("Header layout sanity — magic + version + reserved zeros")
    func headerLayoutSanity() throws {
        let key = SymmetricKey(size: .bits256)
        let env = try BucketeerEnvelope.seal(plaintext: Data(), key: key)
        let bytes = Array(env.prefix(BucketeerEnvelope.headerSize))
        #expect(Array(bytes.prefix(4)) == BucketeerEnvelope.magic)
        #expect(bytes[4] == BucketeerEnvelope.version)
        #expect(Array(bytes.suffix(3)) == BucketeerEnvelope.reservedZeroes)
    }

    @Test("looksEncrypted on partial header returns false")
    func looksEncryptedShortHeader() {
        // 3 bytes of the magic — not enough.
        let partial = Data([0x42, 0x43, 0x4B])
        #expect(!BucketeerEnvelope.looksEncrypted(partial))
    }

    @Test("Open with the wrong key throws authenticationFailed, not badEnvelope")
    func wrongKeyDistinguished() throws {
        let k1 = SymmetricKey(size: .bits256)
        let k2 = SymmetricKey(size: .bits256)
        let env = try BucketeerEnvelope.seal(plaintext: Data("payload".utf8), key: k1)
        do {
            _ = try BucketeerEnvelope.open(envelope: env, key: k2)
            #expect(Bool(false), "wrong key should fail")
        } catch let error as EncryptionError {
            #expect(error == .authenticationFailed)
        }
    }
}
