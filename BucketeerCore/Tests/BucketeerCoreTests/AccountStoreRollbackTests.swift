//
//  AccountStoreRollbackTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 23.11.26.
//

import Foundation
import SQLite3
import SwiftData
import Testing
@testable import BucketeerCore

/// A failed save must not leave its insert pending in the context: the
/// next successful save would persist an account whose credentials the
/// caller already rolled back.
@Suite("AccountStore rollback")
struct AccountStoreRollbackTests {

    @Test("A failed save is not persisted by the next successful save")
    func failedSaveIsDiscarded() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "AccountStoreRollbackTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Bucketeer.store")
        let store = AccountStore(modelContainer: try SharedStore.makeContainer(url: storeURL, allowsSave: true))
        let failing = S3Account(name: "A", provider: .awsS3)
        let unrelated = S3Account(name: "B", provider: .awsS3)

        // A trigger stands in for a transient write failure (disk full,
        // locked store) and is lifted before the second save. It fails at
        // run time: RAISE would read as a uniqueness conflict, which Core
        // Data resolves without throwing.
        var db: OpaquePointer?
        guard sqlite3_open(storeURL.path, &db) == SQLITE_OK else { throw BucketeerError.unknown(message: "open") }
        defer { sqlite3_close(db) }
        try exec(db, "CREATE TRIGGER reject_insert BEFORE INSERT ON ZS3ACCOUNTRECORD BEGIN SELECT json('rejected'); END;")
        await #expect(throws: BucketeerError.self) { try await store.upsert(failing) }
        try exec(db, "DROP TRIGGER reject_insert;")

        try await store.upsert(unrelated)

        let reopened = AccountStore(modelContainer: try SharedStore.makeContainer(url: storeURL, allowsSave: false))
        #expect(try await reopened.all().map(\.id) == [unrelated.id])
    }

    private func exec(_ db: OpaquePointer?, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw BucketeerError.unknown(message: String(cString: sqlite3_errmsg(db)))
        }
    }
}
