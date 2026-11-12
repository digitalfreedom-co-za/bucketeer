//
//  StreamingEnvelope.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 12.11.26.
//

import CryptoKit
import Foundation

/// Version 0x02 of the Bucketeer envelope. The payload is cut into
/// fixed-size segments and every segment is its own AES-256-GCM message,
/// so objects of any size are sealed and opened with memory bounded by
/// the segment size. The byte layout is specified in
/// `docs/ARCHITECTURE.md`, section "Encryption envelope".
///
/// ```
/// header   51 bytes  magic "BCKT" | 0x02 | 3 reserved zero bytes |
///                    segment size (UInt32 BE) | salt (32) | nonce prefix (7)
/// segment  n times   ciphertext (segment size, the last one 0...segment size) | tag (16)
/// ```
///
/// Each object gets its own subkey, HKDF-SHA256 over the bucket key with
/// the random salt, so nonces never repeat across objects. The nonce is
/// `prefix | index (UInt32 BE) | final flag`; the AAD is the full header
/// followed by the same index and flag. Reordering, dropping, duplicating
/// or appending segments, and cutting off the final one, therefore fail
/// authentication.
public extension BucketeerEnvelope {
    static let streamingVersion: UInt8 = 0x02
    static let defaultSegmentSize = 1 << 20
    /// Readers refuse other sizes, so a forged header cannot force a
    /// large allocation.
    static let segmentSizeRange = 64...(16 << 20)
    static let tagSize = 16
    static let streamingHeaderSize = StreamingHeader.size

    /// Object size of a v0x02 envelope for `plaintextLength` bytes:
    /// header + plaintext + one tag per segment, where an empty payload
    /// still has one (empty, final) segment. Throws `badEnvelope` for a
    /// negative length, an unsupported segment size or more segments than
    /// the UInt32 segment index can address.
    static func encryptedLength(plaintextLength: Int64, segmentSize: Int = defaultSegmentSize) throws -> Int64 {
        guard plaintextLength >= 0, segmentSizeRange.contains(segmentSize) else {
            throw EncryptionError.badEnvelope
        }
        let size = Int64(segmentSize)
        let segments = max(1, plaintextLength / size + (plaintextLength % size == 0 ? 0 : 1))
        guard segments <= StreamLayout.maxSegmentCount else { throw EncryptionError.badEnvelope }
        // At most 2^32 segments of at most 16 MiB: the sum stays far below Int64.max.
        return Int64(streamingHeaderSize) + plaintextLength + segments * Int64(tagSize)
    }

    /// Inverse of `encryptedLength`. Throws `badEnvelope` for a length no
    /// v0x02 envelope with this segment size can have.
    static func plaintextLength(encryptedLength: Int64, segmentSize: Int = defaultSegmentSize) throws -> Int64 {
        try StreamLayout(encryptedLength: encryptedLength, segmentSize: segmentSize).plaintextLength
    }

    /// Encrypts the file at `source` into a new v0x02 envelope at
    /// `destination` (owner-only permissions, replaced if present). Holds at most two plaintext segments and one sealed
    /// segment in memory; checks for task cancellation per segment.
    static func sealFile(at source: URL, to destination: URL, key: SymmetricKey,
                         segmentSize: Int = defaultSegmentSize) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        try writing(to: destination, ownerOnly: true) { output in
            try sealStream(key: key, segmentSize: segmentSize,
                           read: { try input.read(upToCount: $0) ?? Data() },
                           write: { try output.write(contentsOf: $0) })
        }
    }

    /// Decrypts a v0x01 or v0x02 envelope at `source` into `destination`.
    /// v0x02 is processed segment by segment; v0x01 is a single GCM
    /// message and stays an in-memory legacy path. On any error the
    /// partial `destination` is removed.
    static func openFile(at source: URL, to destination: URL, key: SymmetricKey) throws {
        try authenticate(fileAt: source, key: key, into: destination)
    }

    /// Whether the file holds an envelope that authenticates under `key`,
    /// with the same fallback rules as `decryptedPayload`: nil key or
    /// structurally invalid unmarked bytes are plain. Nothing is written.
    static func payloadIsEncrypted(at url: URL, marked: Bool, key: SymmetricKey?) throws -> Bool {
        try classify(fileAt: url, marked: marked, key: key, into: nil)
    }

    // MARK: - Internal codec

    /// Seals everything `read` yields. `read(n)` returns at most `n`
    /// bytes and an empty value at the end of input.
    internal static func sealStream(key: SymmetricKey, segmentSize: Int = defaultSegmentSize,
                                    read: (Int) throws -> Data, write: (Data) throws -> Void) throws {
        guard segmentSizeRange.contains(segmentSize) else { throw EncryptionError.badEnvelope }
        let header = StreamingHeader(segmentSize: segmentSize)
        let cipher = SegmentCipher(key: key, header: header)
        try write(header.bytes)
        var index: UInt32 = 0
        var current = try readFully(segmentSize, from: read)
        var isFinal = false
        while !isFinal {
            // Foundation hands out autoreleased buffers (file reads may
            // even be mapped); without a pool per segment they would
            // pile up until the whole payload was processed.
            try autoreleasepool {
                try Task.checkCancellation()
                // A full segment is final only if nothing follows it; an
                // empty payload is one empty final segment.
                let next = current.count == segmentSize ? try readFully(segmentSize, from: read) : Data()
                isFinal = next.isEmpty
                try write(cipher.seal(current, index: index, isFinal: isFinal))
                guard !isFinal else { return }
                guard index < UInt32.max else { throw EncryptionError.badEnvelope }
                index += 1
                current = next
            }
        }
    }

    /// Opens a v0x02 envelope of `encryptedLength` bytes. Every segment is
    /// authenticated before its plaintext reaches `write`, but a truncated
    /// envelope is only detected at its end: callers must discard what
    /// they wrote when this throws.
    internal static func openStream(encryptedLength: Int64, key: SymmetricKey,
                                    read: (Int) throws -> Data, write: (Data) throws -> Void) throws {
        let header = try StreamingHeader(parsing: readFully(StreamingHeader.size, from: read))
        let layout = try StreamLayout(encryptedLength: encryptedLength, segmentSize: header.segmentSize)
        let cipher = SegmentCipher(key: key, header: header)
        for index in 0..<layout.segmentCount {
            try autoreleasepool {
                try Task.checkCancellation()
                let isFinal = index == layout.segmentCount - 1
                let length = isFinal ? layout.finalSegmentLength : header.segmentSize + tagSize
                let segment = try readFully(length, from: read)
                guard segment.count == length else { throw EncryptionError.badEnvelope }
                try write(cipher.open(segment, index: UInt32(index), isFinal: isFinal))
            }
        }
    }

    /// Structural check without a key: a v0x02 header with zero reserved
    /// bytes, a supported segment size and a consistent total length.
    internal static func isStreamingEnvelope(prefix: Data, totalLength: Int64) -> Bool {
        guard prefix.count >= StreamingHeader.size,
              prefix.starts(with: magic + [streamingVersion] + reservedZeroes),
              let header = try? StreamingHeader(parsing: prefix.prefix(StreamingHeader.size)) else {
            return false
        }
        return (try? StreamLayout(encryptedLength: totalLength, segmentSize: header.segmentSize)) != nil
    }

    /// Shared by download finalisation and detection. Returns false when
    /// the bytes are to be left as they are (plain object); true when an
    /// envelope authenticated, after writing its plaintext to
    /// `destination` if one is given.
    internal static func classify(fileAt url: URL, marked: Bool, key: SymmetricKey?, into destination: URL?) throws -> Bool {
        let (prefix, length) = try readPrefix(of: url)
        guard let key else {
            if marked || isLegacyEnvelope(prefix: prefix, totalLength: length)
                || isStreamingEnvelope(prefix: prefix, totalLength: length) {
                throw EncryptionError.noKeyForBucket
            }
            return false
        }
        guard marked || prefix.starts(with: magic) else { return false }
        do {
            try authenticate(fileAt: url, key: key, into: destination)
            return true
        } catch EncryptionError.badEnvelope where !marked {
            return false
        } catch EncryptionError.unsupportedVersion where !marked {
            return false
        }
    }

    // MARK: - Private

    /// Decrypts (or, without a destination, only authenticates) the
    /// envelope at `url`.
    private static func authenticate(fileAt url: URL, key: SymmetricKey, into destination: URL?) throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        let length = Int64(try input.seekToEnd())
        try input.seek(toOffset: 0)
        let prefix = try input.read(upToCount: magic.count + 1) ?? Data()
        try input.seek(toOffset: 0)
        let streaming = try envelopeVersion(of: prefix) == streamingVersion
        let decrypt: ((Data) throws -> Void) throws -> Void = { write in
            if streaming {
                try openStream(encryptedLength: length, key: key,
                               read: { try input.read(upToCount: $0) ?? Data() }, write: write)
            } else {
                try write(open(envelope: Data(contentsOf: url, options: .mappedIfSafe), key: key))
            }
        }
        if let destination {
            try writing(to: destination) { output in try decrypt { try output.write(contentsOf: $0) } }
        } else {
            try decrypt { _ in }
        }
    }

    /// Runs `body` against a fresh file at `url` and removes the file
    /// again if `body` throws. Ciphertext for upload is owner-only;
    /// decrypted output keeps default permissions because it becomes the
    /// user's file.
    private static func writing(to url: URL, ownerOnly: Bool = false, _ body: (FileHandle) throws -> Void) throws {
        let attributes: [FileAttributeKey: Any]? = ownerOnly ? [.posixPermissions: 0o600] : nil
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: attributes) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        do {
            let output = try FileHandle(forWritingTo: url)
            defer { try? output.close() }
            try body(output)
            try output.synchronize()
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private static func readPrefix(of url: URL) throws -> (Data, Int64) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: StreamingHeader.size) ?? Data()
        let length = Int64(try handle.seekToEnd())
        return (prefix, length)
    }

    /// Loops until `count` bytes arrived or the input ended.
    private static func readFully(_ count: Int, from read: (Int) throws -> Data) throws -> Data {
        var buffer = try read(count)
        while buffer.count < count {
            let chunk = try read(count - buffer.count)
            if chunk.isEmpty { break }
            buffer.append(chunk)
        }
        return buffer
    }
}

/// The parsed v0x02 header. `bytes` is exactly what the AAD of every
/// segment starts with.
struct StreamingHeader {
    static let saltSize = 32
    static let noncePrefixSize = 7
    private static let segmentSizeOffset = 8
    private static let saltOffset = segmentSizeOffset + 4
    private static let noncePrefixOffset = saltOffset + saltSize
    static let size = noncePrefixOffset + noncePrefixSize

    let bytes: Data
    let segmentSize: Int

    var salt: Data { bytes.subdata(in: Self.saltOffset..<Self.noncePrefixOffset) }
    var noncePrefix: Data { bytes.subdata(in: Self.noncePrefixOffset..<Self.size) }

    init(segmentSize: Int) {
        var bytes = Data(BucketeerEnvelope.magic)
        bytes.append(BucketeerEnvelope.streamingVersion)
        bytes.append(contentsOf: BucketeerEnvelope.reservedZeroes)
        withUnsafeBytes(of: UInt32(segmentSize).bigEndian) { bytes.append(contentsOf: $0) }
        bytes.append(Self.randomBytes(Self.saltSize))
        bytes.append(Self.randomBytes(Self.noncePrefixSize))
        self.bytes = bytes
        self.segmentSize = segmentSize
    }

    /// Reserved bytes are not checked here: they are authenticated, so a
    /// change fails every segment instead of passing as plain bytes.
    init(parsing data: Data) throws {
        let bytes = Data([UInt8](data)) // zero-based, whatever slice came in
        guard bytes.count >= BucketeerEnvelope.magic.count + 1,
              bytes.starts(with: BucketeerEnvelope.magic) else {
            throw EncryptionError.badEnvelope
        }
        guard bytes[BucketeerEnvelope.magic.count] == BucketeerEnvelope.streamingVersion else {
            throw EncryptionError.unsupportedVersion
        }
        guard bytes.count == Self.size else { throw EncryptionError.badEnvelope }
        let segmentSize = bytes[Self.segmentSizeOffset..<Self.saltOffset].reduce(0) { $0 << 8 | Int($1) }
        guard BucketeerEnvelope.segmentSizeRange.contains(segmentSize) else {
            throw EncryptionError.badEnvelope
        }
        self.bytes = bytes
        self.segmentSize = segmentSize
    }

    /// `SystemRandomNumberGenerator` is the kernel CSPRNG
    /// (`arc4random_buf`) on Apple platforms and cannot fail.
    private static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

/// Segment count and final segment size implied by an envelope length.
/// Every segment but the last carries a full segment of plaintext; the
/// last carries 1...segment size bytes, or 0 when it is the only one.
struct StreamLayout {
    /// The segment index is a UInt32.
    static let maxSegmentCount = Int64(UInt32.max) + 1

    let segmentCount: Int64
    /// Ciphertext plus tag of the final segment.
    let finalSegmentLength: Int
    let plaintextLength: Int64

    init(encryptedLength: Int64, segmentSize: Int) throws {
        let tag = Int64(BucketeerEnvelope.tagSize)
        // Validate before any arithmetic so extreme inputs cannot overflow.
        guard BucketeerEnvelope.segmentSizeRange.contains(segmentSize),
              encryptedLength >= Int64(StreamingHeader.size) + tag else {
            throw EncryptionError.badEnvelope
        }
        let stride = Int64(segmentSize) + tag
        let body = encryptedLength - Int64(StreamingHeader.size)
        let count = body / stride + (body % stride == 0 ? 0 : 1)
        let last = body - (count - 1) * stride
        guard count <= Self.maxSegmentCount, last >= (count == 1 ? tag : tag + 1) else {
            throw EncryptionError.badEnvelope
        }
        segmentCount = count
        finalSegmentLength = Int(last)
        plaintextLength = body - count * tag
    }
}

/// AES-256-GCM under the per-object subkey.
struct SegmentCipher {
    private static let info = Data("Bucketeer envelope v2 segment key".utf8)

    private let key: SymmetricKey
    private let header: StreamingHeader

    init(key: SymmetricKey, header: StreamingHeader) {
        self.key = HKDF<SHA256>.deriveKey(inputKeyMaterial: key, salt: header.salt,
                                          info: Self.info, outputByteCount: 32)
        self.header = header
    }

    func seal(_ plaintext: Data, index: UInt32, isFinal: Bool) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce(index: index, isFinal: isFinal),
                                   authenticating: aad(index: index, isFinal: isFinal))
        return box.ciphertext + box.tag
    }

    func open(_ segment: Data, index: UInt32, isFinal: Bool) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(nonce: nonce(index: index, isFinal: isFinal),
                                            ciphertext: segment.dropLast(BucketeerEnvelope.tagSize),
                                            tag: segment.suffix(BucketeerEnvelope.tagSize))
            return try AES.GCM.open(box, using: key, authenticating: aad(index: index, isFinal: isFinal))
        } catch {
            throw EncryptionError.authenticationFailed
        }
    }

    private func nonce(index: UInt32, isFinal: Bool) throws -> AES.GCM.Nonce {
        try AES.GCM.Nonce(data: header.noncePrefix + Self.position(index: index, isFinal: isFinal))
    }

    private func aad(index: UInt32, isFinal: Bool) -> Data {
        header.bytes + Self.position(index: index, isFinal: isFinal)
    }

    /// Segment index (UInt32 big-endian) followed by the final flag.
    private static func position(index: UInt32, isFinal: Bool) -> Data {
        var data = withUnsafeBytes(of: index.bigEndian) { Data($0) }
        data.append(isFinal ? 0x01 : 0x00)
        return data
    }
}
