//
//  StreamingEnvelopeTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 12.11.26.
//

import CryptoKit
import Foundation
import Testing
@testable import BucketeerCore

@Suite("Streaming envelope (v0x02)")
struct StreamingEnvelopeTests {
    private static let fixtureKey = SymmetricKey(data: Data(0..<32))
    private static let smallSegment = 64

    @Test("A 64 MiB file round-trips while the codec never handles more than one segment per call")
    func largeRoundTripIsBounded() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let segmentSize = BucketeerEnvelope.defaultSegmentSize
        let plainURL = directory.appendingPathComponent("plain")
        let sealedURL = directory.appendingPathComponent("sealed")
        // 64 MiB plus a partial segment, generated chunk by chunk.
        let plaintextLength = Int64(64 * segmentSize + 12345)
        let expectedDigest = try writePattern(to: plainURL, length: plaintextLength)
        let key = SymmetricKey(size: .bits256)

        var largestSealIO = 0
        let input = try FileHandle(forReadingFrom: plainURL)
        _ = FileManager.default.createFile(atPath: sealedURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: sealedURL)
        try BucketeerEnvelope.sealStream(key: key, segmentSize: segmentSize, read: { count in
            largestSealIO = max(largestSealIO, count)
            return try input.read(upToCount: count) ?? Data()
        }, write: { data in
            largestSealIO = max(largestSealIO, data.count)
            try output.write(contentsOf: data)
        })
        try input.close()
        try output.close()
        let sealedLength = try fileSize(sealedURL)
        #expect(try sealedLength == BucketeerEnvelope.encryptedLength(plaintextLength: plaintextLength))
        #expect(try BucketeerEnvelope.plaintextLength(encryptedLength: sealedLength) == plaintextLength)

        var largestOpenIO = 0
        var hasher = SHA256()
        let sealedInput = try FileHandle(forReadingFrom: sealedURL)
        defer { try? sealedInput.close() }
        try BucketeerEnvelope.openStream(encryptedLength: sealedLength, key: key, read: { count in
            largestOpenIO = max(largestOpenIO, count)
            return try sealedInput.read(upToCount: count) ?? Data()
        }, write: { data in
            largestOpenIO = max(largestOpenIO, data.count)
            hasher.update(data: data)
        })
        #expect(Data(hasher.finalize()) == expectedDigest)
        #expect(largestSealIO <= segmentSize + BucketeerEnvelope.tagSize)
        #expect(largestOpenIO <= segmentSize + BucketeerEnvelope.tagSize)
    }

    struct Fixture: Sendable {
        let hex: String
        let plaintext: Data
    }

    /// Explicitly typed so the test macro does not have to infer a tuple
    /// array from long string concatenations.
    static let fixtures: [Fixture] = [
        // v0x01: header, nonce A0…AB, AES-GCM over the whole payload.
        Fixture(hex: "42434b5401000000a0a1a2a3a4a5a6a7a8a9aaaba46d1f4620bf67da1045f1e37f4af1fe1cc93e71f1ce620af57652f30d"
            + "ce7f413abf72101c263ab5c5b78a5e5d1181",
            plaintext: Data("Bucketeer v0x01 legacy fixture\n".utf8)),
        // v0x02: 64-byte segments, salt 10…2F, nonce prefix C0…C6, 100 bytes (i * 7 + 3).
        Fixture(hex: "42434b540200000000000040101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2fc0c1c2c3"
            + "c4c5c63b202b6ef4296cad7a37c6612953019d7def343aeb1f7d27bc5f75d4258d40103e41b052a6b9d289d3bd79ba5e"
            + "37024e66266b01bdf52b22724388d91a8eb6f9b7c1d5662889f98a443d3440a885bd39ee404a8eb494beee08b592bf8d"
            + "218fa33382b755d0e3777b4b44cdde97a21509dc8a97bcdb8062efd838f7fa6ce28e5eecd3c6db",
            plaintext: Data((0..<100).map { (index: Int) -> UInt8 in UInt8(truncatingIfNeeded: index * 7 + 3) }))
    ]

    @Test("Fixtures written outside the app decrypt through the file path", arguments: fixtures)
    func fixturesDecrypt(fixture: Fixture) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for marked in [true, false] {
            let url = directory.appendingPathComponent("object-\(marked)")
            try Self.data(hex: fixture.hex).write(to: url)
            try BucketeerEnvelope.finalizeDownload(at: url, marked: marked, key: Self.fixtureKey)
            #expect(try Data(contentsOf: url) == fixture.plaintext)
        }
    }

    enum Tamper: String, CaseIterable {
        case dropFinalSegment, cutMidSegment, reorderSegments, appendSegment, flipByte, changeSalt, changeSegmentSize

        func apply(to envelope: Data) -> Data {
            let header = BucketeerEnvelope.streamingHeaderSize
            let stride = StreamingEnvelopeTests.smallSegment + BucketeerEnvelope.tagSize
            var bytes = [UInt8](envelope)
            switch self {
            case .dropFinalSegment: bytes.removeLast(bytes.count - header - 3 * stride)
            case .cutMidSegment: bytes.removeLast(50)
            case .reorderSegments: bytes.replaceSubrange(header..<header + 2 * stride,
                                                         with: bytes[header + stride..<header + 2 * stride]
                                                             + bytes[header..<header + stride])
            case .appendSegment: bytes += bytes[header + stride..<header + 2 * stride]
            case .flipByte: bytes[header + stride + 5] ^= 0x01
            case .changeSalt: bytes[20] ^= 0x01
            case .changeSegmentSize: bytes[11] += 1
            }
            return Data(bytes)
        }
    }

    @Test("Tampered envelopes fail authentication and leave the downloaded file untouched",
          arguments: Tamper.allCases)
    func tamperingFails(tamper: Tamper) throws {
        let key = SymmetricKey(size: .bits256)
        // Three full segments and a 10-byte final one.
        let plaintext = Data((0..<(3 * Self.smallSegment + 10)).map { UInt8(truncatingIfNeeded: $0) })
        let tampered = tamper.apply(to: try Self.seal(plaintext, segmentSize: Self.smallSegment, key: key))
        #expect(throws: EncryptionError.authenticationFailed) {
            try BucketeerEnvelope.open(envelope: tampered, key: key)
        }

        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("object")
        try tampered.write(to: url)
        #expect(throws: EncryptionError.authenticationFailed) {
            try BucketeerEnvelope.finalizeDownload(at: url, marked: true, key: key)
        }
        #expect(try Data(contentsOf: url) == tampered)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["object"])
    }

    @Test("Segment boundaries round-trip through the file API with the predicted length",
          arguments: [0, 1, 64, 128, 129] as [Int])
    func segmentBoundaries(length: Int) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let plainURL = directory.appendingPathComponent("plain")
        let sealedURL = directory.appendingPathComponent("sealed")
        let openedURL = directory.appendingPathComponent("opened")
        try plaintext.write(to: plainURL)

        try BucketeerEnvelope.sealFile(at: plainURL, to: sealedURL, key: key, segmentSize: Self.smallSegment)
        let sealedLength = try fileSize(sealedURL)
        #expect(try sealedLength == BucketeerEnvelope.encryptedLength(plaintextLength: Int64(length),
                                                                  segmentSize: Self.smallSegment))
        #expect(try BucketeerEnvelope.plaintextLength(encryptedLength: sealedLength,
                                                      segmentSize: Self.smallSegment) == Int64(length))
        try BucketeerEnvelope.openFile(at: sealedURL, to: openedURL, key: key)
        #expect(try Data(contentsOf: openedURL) == plaintext)
    }

    /// Segment count at which the UInt32 segment index runs out.
    private static let indexLimit = Int64(UInt32.max) + 1

    static let invalidPlaintextLengths: [(Int64, Int)] = [
        (-1, smallSegment),
        (0, 0),
        (0, Int.max),
        (Int64.max, BucketeerEnvelope.defaultSegmentSize),
        (indexLimit * Int64(smallSegment) + 1, smallSegment)
    ]

    @Test("Length calculations reject impossible inputs instead of trapping",
          arguments: invalidPlaintextLengths)
    func encryptedLengthRejects(length: Int64, segmentSize: Int) {
        #expect(throws: EncryptionError.badEnvelope) {
            try BucketeerEnvelope.encryptedLength(plaintextLength: length, segmentSize: segmentSize)
        }
    }

    static let invalidEncryptedLengths: [(Int64, Int)] = [
        (Int64.min, smallSegment),
        (Int64.max, smallSegment),
        (Int64.max, 0),
        (Int64.max, Int.max)
    ]

    @Test("Envelope lengths no v0x02 object can have throw instead of trapping",
          arguments: invalidEncryptedLengths)
    func plaintextLengthRejects(length: Int64, segmentSize: Int) {
        #expect(throws: EncryptionError.badEnvelope) {
            try BucketeerEnvelope.plaintextLength(encryptedLength: length, segmentSize: segmentSize)
        }
    }

    @Test("The largest addressable payload maps back to itself")
    func indexLimitRoundTrips() throws {
        let length = Self.indexLimit * Int64(Self.smallSegment)
        let encrypted = try BucketeerEnvelope.encryptedLength(plaintextLength: length, segmentSize: Self.smallSegment)
        #expect(try BucketeerEnvelope.plaintextLength(encryptedLength: encrypted, segmentSize: Self.smallSegment) == length)
    }

    // MARK: - Helpers

    private static func seal(_ plaintext: Data, segmentSize: Int, key: SymmetricKey) throws -> Data {
        var offset = 0
        var output = Data()
        try BucketeerEnvelope.sealStream(key: key, segmentSize: segmentSize, read: { count in
            let end = min(offset + count, plaintext.count)
            defer { offset = end }
            return plaintext.subdata(in: offset..<end)
        }, write: { output.append($0) })
        return output
    }

    private static func data(hex: String) -> Data {
        let digits = Array(hex.utf8)
        return Data(stride(from: 0, to: digits.count, by: 2).compactMap {
            UInt8(String(decoding: digits[$0...$0 + 1], as: UTF8.self), radix: 16)
        })
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StreamingEnvelopeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber).int64Value
    }

    /// Writes a deterministic pattern in 1 MiB chunks and returns its SHA-256.
    private func writePattern(to url: URL, length: Int64) throws -> Data {
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var written: Int64 = 0
        var chunkIndex: UInt8 = 0
        while written < length {
            let count = Int(min(Int64(1 << 20), length - written))
            let chunk = Data((0..<count).map { UInt8(truncatingIfNeeded: $0) &+ chunkIndex })
            hasher.update(data: chunk)
            try handle.write(contentsOf: chunk)
            written += Int64(count)
            chunkIndex &+= 1
        }
        return Data(hasher.finalize())
    }
}
