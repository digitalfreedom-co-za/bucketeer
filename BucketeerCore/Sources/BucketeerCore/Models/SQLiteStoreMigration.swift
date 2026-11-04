//
//  SQLiteStoreMigration.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import SQLite3

/// Copies a SQLite store (SwiftData) to a new location so that the
/// destination either holds a complete, consistent database or does not
/// exist at all.
///
/// SQLite's online backup reads the store through SQLite itself, so
/// rows still in the write-ahead log are included and no `-wal`/`-shm`
/// sidecar has to be copied. The copy is written to a staging file,
/// checked with `PRAGMA integrity_check`, and only then renamed onto the
/// destination path. The source is never modified.
public enum SQLiteStoreMigration {

    public static func migrate(from source: URL, to destination: URL) throws {
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).migrating-\(UUID().uuidString)")
        do {
            try backUp(source, into: staging)
            // `moveItem` is a rename on one volume and refuses to replace
            // an existing file, so a store that appeared meanwhile wins.
            try FileManager.default.moveItem(at: staging, to: destination)
            // SQLite may leave an empty `-shm` beside the closed copy.
            removeStaging(staging)
        } catch {
            removeStaging(staging)
            throw error as? BucketeerError ?? BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }

    private static func backUp(_ source: URL, into staging: URL) throws {
        let reader = try open(source, flags: SQLITE_OPEN_READONLY)
        defer { sqlite3_close(reader) }
        let writer = try open(staging, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        defer { sqlite3_close(writer) }

        guard let backup = sqlite3_backup_init(writer, "main", reader, "main") else {
            throw failure(writer)
        }
        let step = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard step == SQLITE_DONE, finish == SQLITE_OK else { throw failure(writer) }
        // The copy inherits the source's WAL mode; switching it to a
        // rollback journal folds everything into the one file that is
        // renamed into place. SwiftData turns WAL back on when it opens.
        guard sqlite3_exec(writer, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else {
            throw failure(writer)
        }
        try checkIntegrity(writer)
    }

    private static func open(_ url: URL, flags: Int32) throws -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
            defer { sqlite3_close(db) }
            throw failure(db)
        }
        return db
    }

    private static func checkIntegrity(_ db: OpaquePointer?) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &statement, nil) == SQLITE_OK else {
            throw failure(db)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0),
              String(cString: text) == "ok"
        else {
            throw BucketeerError.persistenceFailure(message: "The migrated store failed SQLite's integrity check.")
        }
    }

    private static func failure(_ db: OpaquePointer?) -> BucketeerError {
        .persistenceFailure(message: db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the store.")
    }

    private static func removeStaging(_ staging: URL) {
        for suffix in ["", "-journal", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: staging.path + suffix)
        }
    }
}
