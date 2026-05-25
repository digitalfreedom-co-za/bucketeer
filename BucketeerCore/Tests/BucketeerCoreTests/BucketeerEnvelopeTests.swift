//
//  BucketeerEnvelopeTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import CryptoKit
import Testing
@testable import BucketeerCore

@Suite("BucketeerEnvelope")
struct BucketeerEnvelopeTests {

    @Test("seal / open round-trips with the same key")
    func roundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("hello bucketeer".utf8)
        let envelope = try BucketeerEnvelope.seal(plaintext: plaintext, key: key)
        let recovered = try BucketeerEnvelope.open(envelope: envelope, key: key)
        #expect(recovered == plaintext)
    }

    @Test("Envelope header carries the BCKT magic + version byte")
    func headerLayout() throws {
        let key = SymmetricKey(size: .bits256)
        let envelope = try BucketeerEnvelope.seal(plaintext: Data([0x01, 0x02]), key: key)
        #expect(Array(envelope.prefix(4)) == BucketeerEnvelope.magic)
        #expect(envelope[envelope.startIndex + 4] == BucketeerEnvelope.version)
    }

    @Test("Opening with a different key fails authentication")
    func wrongKeyFails() throws {
        let k1 = SymmetricKey(size: .bits256)
        let k2 = SymmetricKey(size: .bits256)
        let envelope = try BucketeerEnvelope.seal(plaintext: Data("payload".utf8), key: k1)
        do {
            _ = try BucketeerEnvelope.open(envelope: envelope, key: k2)
            #expect(Bool(false), "Expected authentication failure")
        } catch let error as EncryptionError {
            #expect(error == .authenticationFailed)
        }
    }

    @Test("Garbage data is rejected as badEnvelope")
    func garbageRejected() {
        let key = SymmetricKey(size: .bits256)
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        do {
            _ = try BucketeerEnvelope.open(envelope: garbage, key: key)
            #expect(Bool(false), "Expected badEnvelope")
        } catch let error as EncryptionError {
            #expect(error == .badEnvelope)
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    @Test("looksEncrypted catches Bucketeer envelopes and ignores plain data")
    func recognisesPrefix() throws {
        let key = SymmetricKey(size: .bits256)
        let envelope = try BucketeerEnvelope.seal(plaintext: Data("x".utf8), key: key)
        #expect(BucketeerEnvelope.looksEncrypted(envelope))
        #expect(!BucketeerEnvelope.looksEncrypted(Data("hello".utf8)))
        #expect(!BucketeerEnvelope.looksEncrypted(Data()))
    }

    @Test("Tampering with the ciphertext flips authentication")
    func tamperingDetected() throws {
        let key = SymmetricKey(size: .bits256)
        var envelope = try BucketeerEnvelope.seal(
            plaintext: Data("the quick brown fox".utf8),
            key: key
        )
        // Flip a single ciphertext byte well past the header.
        let flipIndex = envelope.startIndex + BucketeerEnvelope.headerSize + BucketeerEnvelope.nonceSize + 2
        envelope[flipIndex] ^= 0xFF
        do {
            _ = try BucketeerEnvelope.open(envelope: envelope, key: key)
            #expect(Bool(false), "Tampered envelope should fail authentication")
        } catch let error as EncryptionError {
            #expect(error == .authenticationFailed)
        }
    }
}
