//
//  SQLiteStoreMigrationTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import SQLite3
import Testing
@testable import BucketeerCore

/// Moving the store into the App Group must produce either a complete
/// copy or nothing: a partial store would be accepted on every later
/// launch.
@Suite("SQLiteStoreMigration", .serialized)
struct SQLiteStoreMigrationTests {

    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("SQLiteStoreMigrationTests-\(UUID().uuidString)", isDirectory: true)

    @Test("Rows still in the write-ahead log arrive in the migrated store")
    func walContentsAreMigrated() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Source.store")
        let destination = folder.appendingPathComponent("Group/Bucketeer.store")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // The open connection keeps the rows in `-wal`, as a running app would.
        let writer = try open(source)
        defer { sqlite3_close(writer) }
        try exec(writer, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;")
        try exec(writer, "CREATE TABLE account(name TEXT); INSERT INTO account VALUES ('primary'), ('backup');")

        try SQLiteStoreMigration.migrate(from: source, to: destination)

        let listing = try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)
        #expect(listing == ["Bucketeer.store"])
        let reader = try open(destination)
        defer { sqlite3_close(reader) }
        #expect(try count(reader, "SELECT count(*) FROM account") == 2)
    }

    @Test("A source that cannot be read leaves no destination behind")
    func failedMigrationLeavesNothing() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Source.store")
        try Data(repeating: 0x42, count: 8_192).write(to: source)
        let groupFolder = folder.appendingPathComponent("Group", isDirectory: true)
        try FileManager.default.createDirectory(at: groupFolder, withIntermediateDirectories: true)

        #expect(throws: BucketeerError.self) {
            try SQLiteStoreMigration.migrate(from: source, to: groupFolder.appendingPathComponent("Bucketeer.store"))
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: groupFolder.path).isEmpty)
        #expect(try Data(contentsOf: source) == Data(repeating: 0x42, count: 8_192))
    }

    // MARK: - SQLite helpers

    private func open(_ url: URL) throws -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw BucketeerError.unknown(message: "open") }
        return db
    }

    private func exec(_ db: OpaquePointer?, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw BucketeerError.unknown(message: String(cString: sqlite3_errmsg(db)))
        }
    }

    private func count(_ db: OpaquePointer?, _ sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw BucketeerError.unknown(message: "prepare") }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw BucketeerError.unknown(message: "step") }
        return Int(sqlite3_column_int64(statement, 0))
    }
}
