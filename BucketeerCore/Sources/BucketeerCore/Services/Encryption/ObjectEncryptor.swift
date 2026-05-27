//
//  ObjectEncryptor.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import CryptoKit

/// Bucketeer's wire envelope for client-side-encrypted objects.
/// Phase 13.15.
///
/// Layout (on-disk / on-wire):
///
/// ```
/// magic       4 bytes  "BCKT"
/// version     1 byte   0x01
/// reserved    3 bytes  zero — for future flag bits
/// nonce      12 bytes  AES-GCM IV
/// ciphertext N bytes   payload (includes the GCM tag at the end)
/// ```
///
/// The format is intentionally simple: no key id is embedded because
/// the user picks the key per bucket via the `EncryptionKeyStore`
/// lookup. A future phase will add a 16-byte key fingerprint after
/// the version byte so multi-key rotation can resolve which key was
/// used.
public enum BucketeerEnvelope {
    public static let magic: [UInt8] = [0x42, 0x43, 0x4B, 0x54] // "BCKT"
    public static let version: UInt8 = 0x01
    public static let reservedZeroes: [UInt8] = [0x00, 0x00, 0x00]
    public static let headerSize: Int = magic.count + 1 + reservedZeroes.count
    public static let nonceSize: Int = 12

    /// Encrypt `plaintext` under `key` and wrap with the Bucketeer
    /// envelope header.
    ///
    /// Codex audit fix (medium #1): the envelope header (magic +
    /// version + reserved) is passed to AES-GCM as *additional
    /// authenticated data* so any tamper with the version byte or
    /// the reserved bits flips the tag check on open. Without this,
    /// an attacker could swap our version byte to a value that a
    /// future relaxed parser accepts and downgrade the format.
    public static func seal(plaintext: Data, key: SymmetricKey) throws -> Data {
        let nonce = AES.GCM.Nonce()
        let header = headerBytes()
        let sealed = try AES.GCM.seal(
            plaintext,
            using: key,
            nonce: nonce,
            authenticating: header
        )
        var output = Data()
        output.reserveCapacity(header.count + nonceSize + sealed.ciphertext.count + sealed.tag.count)
        output.append(header)
        output.append(contentsOf: Array(nonce))
        output.append(sealed.ciphertext)
        output.append(sealed.tag)
        return output
    }

    /// Validate the header, recover the nonce, and decrypt. Throws
    /// `EncryptionError.badEnvelope` for any malformed input and
    /// `EncryptionError.authenticationFailed` when the AES-GCM tag
    /// check fails (wrong key, tampered ciphertext, or tampered
    /// header).
    public static func open(envelope: Data, key: SymmetricKey) throws -> Data {
        // Codex audit fix (low #1): zero-byte plaintexts produce a
        // valid envelope of exactly `headerSize + nonceSize + 16`.
        // The previous strict `>` guard rejected that legitimate
        // case as malformed.
        guard envelope.count >= headerSize + nonceSize + 16 else {
            throw EncryptionError.badEnvelope
        }
        let magicSlice = envelope.prefix(magic.count)
        guard Array(magicSlice) == magic else { throw EncryptionError.badEnvelope }
        let versionByte = envelope[envelope.startIndex + magic.count]
        guard versionByte == version else { throw EncryptionError.unsupportedVersion }

        // Reconstruct the exact bytes we passed as AAD at seal time.
        // Any tamper with the reserved bytes flips the tag check
        // below — Codex audit fix (medium #1).
        let headerData = envelope.prefix(headerSize)

        let nonceStart = envelope.startIndex + headerSize
        let nonceEnd = nonceStart + nonceSize
        let nonceBytes = envelope[nonceStart..<nonceEnd]
        let nonce = try AES.GCM.Nonce(data: nonceBytes)

        // The trailing 16 bytes of every GCM sealed-box are the tag.
        let bodyAndTag = envelope[nonceEnd...]
        guard bodyAndTag.count >= 16 else { throw EncryptionError.badEnvelope }
        let tag = bodyAndTag.suffix(16)
        let ciphertext = bodyAndTag.dropLast(16)

        do {
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            return try AES.GCM.open(box, using: key, authenticating: headerData)
        } catch {
            throw EncryptionError.authenticationFailed
        }
    }

    /// Build the AAD blob. Kept separate so `seal` and `open` are
    /// guaranteed to authenticate the exact same bytes.
    private static func headerBytes() -> Data {
        var header = Data()
        header.reserveCapacity(headerSize)
        header.append(contentsOf: magic)
        header.append(version)
        header.append(contentsOf: reservedZeroes)
        return header
    }

    /// Quick "does this blob look like a Bucketeer-encrypted
    /// object?" check — used by the download path so unprotected
    /// objects pass through untouched.
    public static func looksEncrypted(_ data: Data) -> Bool {
        guard data.count >= headerSize else { return false }
        return Array(data.prefix(magic.count)) == magic
    }
}

/// Domain errors for the encryption layer. Translated to
/// `BucketeerError` at the host boundary.
public enum EncryptionError: Error, Sendable, Equatable {
    case badEnvelope
    case unsupportedVersion
    case authenticationFailed
    case noKeyForBucket
}
