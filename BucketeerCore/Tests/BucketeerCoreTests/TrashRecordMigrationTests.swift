//
//  TrashRecordMigrationTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 12.11.26.
//

import Foundation
import SwiftData
import Testing
@testable import BucketeerCore

struct TrashRecordMigrationTests {
    @Test("A persisted trash record without an encryption marker migrates as unmarked")
    @MainActor
    func legacyRecord() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Trash.store")
        let item = TrashedItem(accountID: UUID(), accountName: "test", bucket: "bucket", key: "key",
                               size: 7, contentType: nil, etag: nil, expiresAt: .distantFuture,
                               cacheStatus: .cached, cachedFileName: "payload")
        try persistLegacy(item, at: url)

        let schema = Schema([TrashRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(container)
        let records = try context.fetch(FetchDescriptor<TrashRecord>())
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(!record.encryptionMarked)
        #expect(record.snapshot == item)
    }

    @MainActor
    private func persistLegacy(_ item: TrashedItem, at url: URL) throws {
        let schema = Schema([LegacyTrash.TrashRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(container)
        context.insert(LegacyTrash.TrashRecord(item: item))
        try context.save()
    }
}

// The stored model before encryptionMarked was added; keep its entity name and attributes.
private enum LegacyTrash {
    @Model
    final class TrashRecord {
        @Attribute(.unique) var id: UUID
        var accountID: UUID
        var accountName: String
        var bucket: String
        var key: String
        var size: Int64
        var contentType: String?
        var etag: String?
        var deletedAt: Date
        var expiresAt: Date
        var cacheStatusRaw: String
        var cachedFileName: String?

        init(item: TrashedItem) {
            self.id = item.id
            self.accountID = item.accountID
            self.accountName = item.accountName
            self.bucket = item.bucket
            self.key = item.key
            self.size = item.size
            self.contentType = item.contentType
            self.etag = item.etag
            self.deletedAt = item.deletedAt
            self.expiresAt = item.expiresAt
            self.cacheStatusRaw = item.cacheStatus.rawValue
            self.cachedFileName = item.cachedFileName
        }
    }
}
