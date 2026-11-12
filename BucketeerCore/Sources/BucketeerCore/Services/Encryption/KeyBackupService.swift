import CommonCrypto
import CryptoKit
import Foundation
import Security

public struct KeyBackupEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let accountID: UUID
    public let accountDisplayName: String?
    public let bucket: String
    public let label: String
    public var rawKey: Data
    public let createdAt: Date

    public init(id: UUID, accountID: UUID, accountDisplayName: String?, bucket: String,
                label: String, rawKey: Data, createdAt: Date) {
        self.id = id
        self.accountID = accountID
        self.accountDisplayName = accountDisplayName
        self.bucket = bucket
        self.label = label
        self.rawKey = rawKey
        self.createdAt = createdAt
    }
}

public struct KeyImportPlan: Identifiable, Sendable {
    public enum State: Sendable { case new, identical, conflict, unknownAccount }
    public let entry: KeyBackupEntry
    public let state: State
    public let existingID: UUID?
    public var id: UUID { entry.id }
}

public enum KeyBackupError: LocalizedError, Equatable, Sendable {
    case badMagic, unsupportedVersion, unsupportedKDF, invalidIterations, invalidPayload
    case authenticationFailed, invalidPassphrase, randomFailure, derivationFailed, staleConflict

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion, .unsupportedKDF:
            String(localized: "encryption.error.unsupportedVersion", bundle: .module)
        case .authenticationFailed:
            String(localized: "encryption.error.authenticationFailed", bundle: .module)
        case .invalidPassphrase:
            String(localized: "encryption.backup.hint", bundle: .module)
        case .staleConflict:
            String(localized: "encryption.backup.conflict", bundle: .module)
        default:
            String(localized: "encryption.error.badEnvelope", bundle: .module)
        }
    }
}

public enum KeyBackupService {
    public static let maximumFileSize = 16 * 1024 * 1024
    private static let magic = Data("BKTKEYX".utf8)
    private static let headerSize = 41
    private static let iterations: UInt32 = 600_000

    public static func seal(_ entries: [KeyBackupEntry], passphrase: String, confirmation: String) throws -> Data {
        guard passphrase.count >= 12, passphrase == confirmation else { throw KeyBackupError.invalidPassphrase }
        try validate(entries)
        let salt = try randomBytes(count: 16)
        let nonceBytes = try randomBytes(count: 12)
        var header = magic
        header.append(contentsOf: [1, 1])
        header.append(contentsOf: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: iterations >> $0) })
        header.append(salt)
        header.append(nonceBytes)
        let key = try derive(passphrase, salt: salt, iterations: iterations)
        var plaintext = try JSONEncoder().encode(entries)
        defer { plaintext.resetBytes(in: plaintext.startIndex..<plaintext.endIndex) }
        guard plaintext.count <= maximumFileSize - headerSize - 16 else { throw KeyBackupError.invalidPayload }
        let box = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(data: nonceBytes), authenticating: header)
        return header + box.ciphertext + box.tag
    }

    public static func open(_ file: Data, passphrase: String) throws -> [KeyBackupEntry] {
        guard file.starts(with: magic) else { throw KeyBackupError.badMagic }
        guard file.count >= headerSize + 16, file.count <= maximumFileSize else { throw KeyBackupError.invalidPayload }
        let bytes = Data(file)
        guard bytes[7] == 1 else { throw KeyBackupError.unsupportedVersion }
        guard bytes[8] == 1 else { throw KeyBackupError.unsupportedKDF }
        let rounds = bytes[9..<13].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard (100_000...10_000_000).contains(rounds) else { throw KeyBackupError.invalidIterations }
        let key = try derive(passphrase, salt: bytes[13..<29], iterations: rounds)
        var plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: bytes[29..<41]),
                                            ciphertext: bytes[headerSize..<(bytes.count - 16)], tag: bytes.suffix(16))
            plaintext = try AES.GCM.open(box, using: key, authenticating: bytes.prefix(headerSize))
        } catch {
            throw KeyBackupError.authenticationFailed
        }
        defer { plaintext.resetBytes(in: plaintext.startIndex..<plaintext.endIndex) }
        let entries: [KeyBackupEntry]
        do { entries = try JSONDecoder().decode([KeyBackupEntry].self, from: plaintext) }
        catch { throw KeyBackupError.invalidPayload }
        try validate(entries)
        return entries
    }

    /// Only encrypted bytes ever reach the filesystem, including atomic staging.
    public static func write(_ ciphertext: Data, to url: URL) throws {
        guard url.pathExtension.lowercased() == "bktkeys", ciphertext.starts(with: magic) else {
            throw KeyBackupError.invalidPayload
        }
        try ciphertext.write(to: url, options: [.atomic, .completeFileProtection])
    }

    public static func read(from url: URL, passphrase: String) throws -> [KeyBackupEntry] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let file = try handle.read(upToCount: maximumFileSize + 1) ?? Data()
        return try open(file, passphrase: passphrase)
    }

    /// Called again at commit time, within the store actor without suspension.
    public static func shouldImport(_ entry: KeyBackupEntry, existing: BucketEncryptionKey?,
                                    existingBytes: Data?, replacing expectedID: UUID?) throws -> Bool {
        guard entry.rawKey.count == 32, !entry.bucket.isEmpty else { throw KeyBackupError.invalidPayload }
        if existingBytes == entry.rawKey { return false }
        if let existing {
            guard let expectedID else { return false }
            guard existing.id == expectedID else { throw KeyBackupError.staleConflict }
        } else if expectedID != nil {
            throw KeyBackupError.staleConflict
        }
        return true
    }

    private static func validate(_ entries: [KeyBackupEntry]) throws {
        var targets: [UUID: Set<String>] = [:]
        var ids: Set<UUID> = []
        for entry in entries {
            guard entry.rawKey.count == 32, !entry.bucket.isEmpty,
                  ids.insert(entry.id).inserted,
                  targets[entry.accountID, default: []].insert(entry.bucket).inserted else {
                throw KeyBackupError.invalidPayload
            }
        }
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw KeyBackupError.randomFailure }
        return bytes
    }

    private static func derive(_ passphrase: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        var password = Array(passphrase.utf8)
        let passwordCount = password.count
        // Ensure a non-null pointer even for an empty import passphrase.
        password.append(0)
        var derived = [UInt8](repeating: 0, count: 32)
        defer {
            _ = password.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
            _ = derived.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
        }
        let status = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                derived.withUnsafeMutableBufferPointer { output in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                        passwordBytes.baseAddress!.assumingMemoryBound(to: CChar.self), passwordCount,
                                        saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                                        output.baseAddress!, output.count)
                }
            }
        }
        guard status == kCCSuccess else { throw KeyBackupError.derivationFailed }
        return SymmetricKey(data: derived)
    }
}

public extension EncryptionKeyStoring {
    /// Nil selects every key; an explicit set selects only those local identities.
    func exportKeys(ids: Set<UUID>?, accountNames: [UUID: String], passphrase: String, confirmation: String) async throws -> Data {
        let keys = try await all().filter { ids?.contains($0.id) ?? true }
        var entries: [KeyBackupEntry] = []
        defer {
            for index in entries.indices { entries[index].rawKey.resetBytes(in: 0..<entries[index].rawKey.count) }
        }
        for key in keys {
            entries.append(KeyBackupEntry(id: key.id, accountID: key.accountID, accountDisplayName: accountNames[key.accountID],
                                          bucket: key.bucket, label: key.label, rawKey: try await keyMaterial(id: key.id), createdAt: key.createdAt))
        }
        return try KeyBackupService.seal(entries, passphrase: passphrase, confirmation: confirmation)
    }

    func importPlan(_ entries: [KeyBackupEntry], knownAccountIDs: Set<UUID>) async throws -> [KeyImportPlan] {
        var plan: [KeyImportPlan] = []
        for entry in entries {
            let existing = try await key(accountID: entry.accountID, bucket: entry.bucket)
            let state: KeyImportPlan.State
            if let existing {
                state = try await keyMaterial(id: existing.id) == entry.rawKey ? .identical : .conflict
            } else {
                state = knownAccountIDs.contains(entry.accountID) ? .new : .unknownAccount
            }
            plan.append(KeyImportPlan(entry: entry, state: state, existingID: existing?.id))
        }
        return plan
    }
}
