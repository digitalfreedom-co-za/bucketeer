//
//  SharedStoreTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

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
