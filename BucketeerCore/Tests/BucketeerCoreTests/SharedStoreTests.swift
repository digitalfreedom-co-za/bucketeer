//
//  SharedStoreTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import CoreData
import Foundation
import SwiftData
import Testing
@testable import BucketeerCore

/// Host and File Provider extension open the same App Group store. The
/// extension's read-only open must never drop the host's sync jobs.
@Suite("SharedStore")
struct SharedStoreTests {

    @Test("Host and extension opens alternate without losing accounts or sync jobs")
    func alternatingOpensKeepAllEntities() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SharedStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Bucketeer.store")

        try seedHostStore(at: storeURL)

        let extensionContainer = try SharedStore.makeContainer(url: storeURL, allowsSave: false)
        let extensionContext = ModelContext(extensionContainer)
        #expect(try extensionContext.fetchCount(FetchDescriptor<S3AccountRecord>()) == 1)

        let hostContainer = try SharedStore.makeContainer(url: storeURL, allowsSave: true)
        let hostContext = ModelContext(hostContainer)
        #expect(try hostContext.fetchCount(FetchDescriptor<S3AccountRecord>()) == 1)
        #expect(try hostContext.fetchCount(FetchDescriptor<SyncJobRecord>()) == 1)
    }

    @Test("Sync jobs stored before the decrypted-copies option open with the option off")
    func legacySyncJobOpensWithoutDecryptedCopies() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SharedStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Bucketeer.store")
        try seedLegacyStore(at: storeURL)

        let container = try SharedStore.makeContainer(url: storeURL, allowsSave: true)
        let records = try ModelContext(container).fetch(FetchDescriptor<SyncJobRecord>())

        #expect(records.count == 1)
        #expect(records.first?.snapshot?.allowsDecryptedCopies == false)
    }

    /// Written through Core Data: SwiftData resolves entities by name per
    /// process, so it would map the legacy row onto the current class.
    private func seedLegacyStore(at url: URL) throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(
            for: [S3AccountRecord.self, LegacySchema.SyncJobRecord.self]
        ))
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
        defer { try? coordinator.remove(store) }
        let context = NSManagedObjectContext(.privateQueue)
        context.persistentStoreCoordinator = coordinator
        let endpoint = try JSONEncoder().encode(SyncEndpoint.s3(accountID: UUID(), bucket: "vault", prefix: ""))
        try context.performAndWait {
            let entity = try #require(model.entitiesByName["SyncJobRecord"])
            let job = NSManagedObject(entity: entity, insertInto: context)
            job.setValue(UUID(), forKey: "id")
            job.setValue("Nightly", forKey: "name")
            job.setValue(SyncMode.copy.rawValue, forKey: "modeRaw")
            job.setValue(endpoint, forKey: "sourceEndpointData")
            job.setValue(endpoint, forKey: "destinationEndpointData")
            job.setValue(SyncDiffStrategy.nameAndSize.rawValue, forKey: "diffStrategyRaw")
            job.setValue([String](), forKey: "includeGlobs")
            job.setValue([String](), forKey: "excludeGlobs")
            job.setValue(false, forKey: "deletePropagation")
            job.setValue(SyncSchedule.manual.rawValue, forKey: "scheduleRaw")
            job.setValue(4, forKey: "concurrency")
            job.setValue(true, forKey: "enabled")
            try context.save()
        }
    }

    private func seedHostStore(at url: URL) throws {
        let container = try SharedStore.makeContainer(url: url, allowsSave: true)
        let context = ModelContext(container)
        let accountID = UUID()
        context.insert(S3AccountRecord(
            id: accountID, name: "Demo", providerRaw: S3Provider.awsS3.rawValue,
            region: "eu-central-1", endpointOverrideRaw: nil, accountID: nil,
            defaultBucket: nil, usesPathStyle: false, lastUsedAt: nil, sortIndex: 0
        ))
        context.insert(SyncJobRecord(job: SyncJob(
            name: "Nightly",
            mode: .copy,
            source: .s3(accountID: accountID, bucket: "a", prefix: ""),
            destination: .s3(accountID: accountID, bucket: "b", prefix: "")
        )))
        try context.save()
    }
}

/// `SyncJobRecord` as released before `allowsDecryptedCopies` existed.
private enum LegacySchema {
    @Model
    final class SyncJobRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var modeRaw: String
        var sourceEndpointData: Data
        var destinationEndpointData: Data
        var diffStrategyRaw: String
        var includeGlobs: [String]
        var excludeGlobs: [String]
        var deletePropagation: Bool
        var scheduleRaw: String
        var concurrency: Int
        var lastRunAt: Date?
        var lastRunSummary: String?
        var enabled: Bool

        init() {
            fatalError("Schema description only; rows are written through Core Data.")
        }
    }
}
