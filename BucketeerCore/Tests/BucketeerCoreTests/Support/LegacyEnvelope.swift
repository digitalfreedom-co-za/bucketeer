//
//  LegacyEnvelope.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 12.11.26.
//

import CryptoKit
import Foundation
@testable import BucketeerCore

/// Writes version 0x01 envelopes, which the app no longer produces but
/// must keep reading: header "BCKT" 0x01 000000 | nonce (12) | ciphertext | tag.
enum LegacyEnvelope {
    static func seal(plaintext: Data, key: SymmetricKey) throws -> Data {
        let header = Data(BucketeerEnvelope.magic + [BucketeerEnvelope.legacyVersion] + BucketeerEnvelope.reservedZeroes)
        let nonce = AES.GCM.Nonce()
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: header)
        return header + Data(Array(nonce)) + box.ciphertext + box.tag
    }
}
