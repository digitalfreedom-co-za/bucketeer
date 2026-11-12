//
//  ObjectEncryptor.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import CryptoKit

/// Bucketeer's wire envelope for client-side-encrypted objects.
/// Phase 13.15; segmented version 0x02 since #39.
///
/// New objects are written as version 0x02 (`StreamingEnvelope.swift`),
/// which seals and opens segment by segment. Version 0x01 is still read:
///
/// ```
/// magic       4 bytes  "BCKT"
/// version     1 byte   0x01
/// reserved    3 bytes  zero — for future flag bits
/// nonce      12 bytes  AES-GCM IV
/// ciphertext N bytes   payload (includes the GCM tag at the end)
/// ```
///
/// No key id is embedded: the user picks the key per bucket via the
/// `EncryptionKeyStore` lookup. Byte-level specification of both
/// versions: `docs/ARCHITECTURE.md`, section "Encryption envelope".
public enum BucketeerEnvelope {
    public static let magic: [UInt8] = [0x42, 0x43, 0x4B, 0x54] // "BCKT"
    public static let legacyVersion: UInt8 = 0x01
    public static let reservedZeroes: [UInt8] = [0x00, 0x00, 0x00]
    public static let legacyHeaderSize: Int = magic.count + 1 + reservedZeroes.count
    public static let legacyNonceSize: Int = 12

    public static let s3MetadataKey = "bucketeer-enc"
    public static let azureMetadataKey = "bucketeerenc"

    public static func isMarked(_ metadata: [String: String]?, name: String = s3MetadataKey) -> Bool {
        metadata?.contains { $0.key.lowercased() == name && $0.value == "1" } == true
    }

    /// A metadata replacement must never strip an existing encryption marker.
    public static func preservingMarker(in metadata: [String: String], from original: [String: String]?,
                                        name: String = s3MetadataKey) -> [String: String] {
        guard isMarked(original, name: name) else { return metadata }
        var result = metadata.filter { $0.key.lowercased() != name }
        result[name] = "1"
        return result
    }

    /// Nil means unchanged plaintext; a value is authenticated plaintext.
    /// Only structural legacy errors permit fallback. Authentication failures
    /// (including reserved-header tampering) always fail closed.
    /// In-memory variant of `finalizeDownload` for small payloads.
    public static func decryptedPayload(_ data: Data, marked: Bool, key: SymmetricKey?) throws -> Data? {
        guard let key else {
            let length = Int64(data.count)
            if marked || isLegacyEnvelope(prefix: data, totalLength: length)
                || isStreamingEnvelope(prefix: data.prefix(streamingHeaderSize), totalLength: length) {
                throw EncryptionError.noKeyForBucket
            }
            return nil
        }
        guard marked || data.starts(with: magic) else { return nil }
        do {
            return try open(envelope: data, key: key)
        } catch EncryptionError.badEnvelope where !marked {
            return nil
        } catch EncryptionError.unsupportedVersion where !marked {
            return nil
        }
    }

    /// Replaces an authenticated envelope at `url` with its plaintext and
    /// leaves plain objects unchanged, with the rules of
    /// `decryptedPayload`. Version 0x02 is decrypted segment by segment
    /// into a sibling file that replaces `url` only after the last
    /// segment authenticated, so memory stays bounded and a failure
    /// leaves `url` untouched.
    public static func finalizeDownload(at url: URL, marked: Bool, key: SymmetricKey?) throws {
        let output = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).decrypting", isDirectory: false)
        do {
            if try classify(fileAt: url, marked: marked, key: key, into: output) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: output)
            }
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        try? FileManager.default.removeItem(at: output)
    }

    /// Encrypt `plaintext` under `key` into a version 0x02 envelope held
    /// in memory. Large payloads go through `sealFile` instead.
    public static func seal(plaintext: Data, key: SymmetricKey) throws -> Data {
        var offset = plaintext.startIndex
        var output = Data()
        output.reserveCapacity(Int(encryptedLength(plaintextLength: Int64(plaintext.count))))
        try sealStream(key: key, read: { count in
            let end = plaintext.index(offset, offsetBy: min(count, plaintext.endIndex - offset))
            defer { offset = end }
            return plaintext.subdata(in: offset..<end)
        }, write: { output.append($0) })
        return output
    }

    /// Validate the header and decrypt a version 0x01 or 0x02 envelope
    /// held in memory. Throws `EncryptionError.badEnvelope` for any
    /// malformed input, `unsupportedVersion` for an unknown version byte
    /// and `authenticationFailed` when a GCM tag check fails (wrong key,
    /// tampered ciphertext, or tampered header).
    public static func open(envelope: Data, key: SymmetricKey) throws -> Data {
        guard try envelopeVersion(of: envelope) == streamingVersion else {
            return try openLegacy(envelope: envelope, key: key)
        }
        var offset = envelope.startIndex
        var output = Data()
        try openStream(encryptedLength: Int64(envelope.count), key: key, read: { count in
            let end = envelope.index(offset, offsetBy: min(count, envelope.endIndex - offset))
            defer { offset = end }
            return envelope.subdata(in: offset..<end)
        }, write: { output.append($0) })
        return output
    }

    /// The version byte of a known envelope.
    internal static func envelopeVersion(of prefix: Data) throws -> UInt8 {
        guard prefix.count > magic.count, prefix.starts(with: magic) else {
            throw EncryptionError.badEnvelope
        }
        let version = prefix[prefix.startIndex + magic.count]
        guard version == legacyVersion || version == streamingVersion else {
            throw EncryptionError.unsupportedVersion
        }
        return version
    }

    /// Structural check without a key, unchanged since #40: a version
    /// 0x01 header with zero reserved bytes and room for nonce and tag.
    internal static func isLegacyEnvelope(prefix: Data, totalLength: Int64) -> Bool {
        totalLength >= Int64(legacyHeaderSize + legacyNonceSize + tagSize) && prefix.starts(with: legacyHeaderBytes())
    }

    /// Version 0x01: one AES-GCM message over the whole payload, with
    /// the 8-byte header as AAD so a tampered version or reserved byte
    /// fails the tag check.
    private static func openLegacy(envelope: Data, key: SymmetricKey) throws -> Data {
        // Zero-byte plaintexts produce a
        // valid envelope of exactly `headerSize + nonceSize + 16`.
        guard envelope.count >= legacyHeaderSize + legacyNonceSize + tagSize else {
            throw EncryptionError.badEnvelope
        }
        guard try envelopeVersion(of: envelope) == legacyVersion else { throw EncryptionError.unsupportedVersion }

        // Reconstruct the exact bytes we passed as AAD at seal time.
        // Any tamper with the reserved bytes flips the tag check
        // below.
        let headerData = envelope.prefix(legacyHeaderSize)

        let nonceStart = envelope.startIndex + legacyHeaderSize
        let nonceEnd = nonceStart + legacyNonceSize
        let nonceBytes = envelope[nonceStart..<nonceEnd]
        let nonce = try AES.GCM.Nonce(data: nonceBytes)

        // The trailing 16 bytes of every GCM sealed-box are the tag.
        let bodyAndTag = envelope[nonceEnd...]
        let tag = bodyAndTag.suffix(tagSize)
        let ciphertext = bodyAndTag.dropLast(tagSize)

        do {
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            return try AES.GCM.open(box, using: key, authenticating: headerData)
        } catch {
            throw EncryptionError.authenticationFailed
        }
    }

    private static func legacyHeaderBytes() -> Data {
        Data(magic + [legacyVersion] + reservedZeroes)
    }
}

/// Errors localized in the shared package for both the app and File Provider.
public enum EncryptionError: LocalizedError, Sendable, Equatable {
    case badEnvelope
    case unsupportedVersion
    case authenticationFailed
    case keyRemoved
    case backupNotConfirmed
    case noKeyForBucket

    public var errorDescription: String? {
        switch self {
        case .badEnvelope:
            String(localized: "encryption.error.badEnvelope", bundle: .module)
        case .unsupportedVersion:
            String(localized: "encryption.error.unsupportedVersion", bundle: .module)
        case .authenticationFailed:
            String(localized: "encryption.error.authenticationFailed", bundle: .module)
        case .keyRemoved:
            String(localized: "encryption.error.keyRemoved", bundle: .module)
        case .backupNotConfirmed:
            String(localized: "encryption.backup.error.notConfirmed", bundle: .module)
        case .noKeyForBucket:
            String(localized: "error.encryptedNoKey", bundle: .module)
        }
    }
}
