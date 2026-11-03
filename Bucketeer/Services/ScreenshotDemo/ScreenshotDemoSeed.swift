//
//  ScreenshotDemoSeed.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

#if DEBUG
import Foundation
import SwiftData
import BucketeerCore

/// Demo content for the screenshot mode, read from the JSON file given
/// with `-BucketeerDemoSeed`. Everything lands in the in-memory stores
/// of a demo `AppContainer`; times are relative to the launch.
struct ScreenshotDemoSeed: Decodable {
    struct Account: Decodable {
        let name: String
        let endpoint: URL
        let region: String
        let accessKey: String
        let secretKey: String
    }

    struct Job: Decodable {
        let name: String
        let mode: SyncMode
        let account: String
        let sourceBucket: String
        let destinationBucket: String
        let schedule: String
        let lastRunHoursAgo: Double
        let lastRunSummary: String
    }

    struct WatchFolder: Decodable {
        let name: String
        let folder: String
        let account: String
        let bucket: String
        let prefix: String
    }

    struct Activity: Decodable {
        let kind: ActivityKind
        let status: ActivityStatus
        let minutesAgo: Double
        let account: String
        let bucket: String?
        let key: String?
        let bytes: Int64?
        let durationMS: Int?
        let syncJob: String?
    }

    struct EncryptionKey: Decodable {
        let label: String
        let account: String
        let bucket: String
        let daysAgo: Double
    }

    /// Where the browser-based shots point.
    struct Showcase: Decodable {
        let account: String
        let bucket: String
        let folder: String
        let object: String
        let versionedFolder: String
        let versionedObject: String
    }

    enum SeedError: Error {
        case unknownAccount(String)
        case invalidSchedule(String)
    }

    let accounts: [Account]
    let syncJobs: [Job]
    let watchFolders: [WatchFolder]
    let activity: [Activity]
    let encryptionKeys: [EncryptionKey]
    let showcase: Showcase

    static func load(path: String) throws -> ScreenshotDemoSeed {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    /// Writes the seed into the container's stores and returns the
    /// created accounts by name.
    @MainActor
    func apply(to container: AppContainer, now: Date = Date()) async throws -> [String: S3Account] {
        var created: [String: S3Account] = [:]
        for entry in accounts {
            let account = S3Account(name: entry.name, provider: .custom, region: entry.region, endpointOverride: entry.endpoint)
            try await container.accountStore.upsert(account)
            try await container.keychainStore.save(
                AccountCredentials(accessKey: entry.accessKey, secretKey: entry.secretKey), for: account.id
            )
            created[entry.name] = account
        }
        func account(_ name: String) throws -> S3Account {
            guard let account = created[name] else { throw SeedError.unknownAccount(name) }
            return account
        }

        var jobIDs: [String: UUID] = [:]
        for job in syncJobs {
            guard let schedule = SyncSchedule(rawValue: job.schedule) else { throw SeedError.invalidSchedule(job.schedule) }
            let accountID = try account(job.account).id
            let syncJob = SyncJob(
                name: job.name,
                mode: job.mode,
                source: .s3(accountID: accountID, bucket: job.sourceBucket, prefix: ""),
                destination: .s3(accountID: accountID, bucket: job.destinationBucket, prefix: ""),
                schedule: schedule,
                lastRunAt: now.addingTimeInterval(-job.lastRunHoursAgo * 3_600),
                lastRunSummary: job.lastRunSummary
            )
            try await container.syncJobStore.upsert(syncJob)
            jobIDs[job.name] = syncJob.id
        }
        // The bookmark stays empty: the demo never starts the sync engine,
        // so the folder is shown but never resolved or watched.
        for folder in watchFolders {
            try await container.syncJobStore.upsert(SyncJob(
                name: folder.name,
                source: .localFolder(bookmark: Data(), displayPath: folder.folder),
                destination: .s3(accountID: try account(folder.account).id, bucket: folder.bucket, prefix: folder.prefix),
                schedule: .onLocalChange
            ))
        }

        for row in activity {
            let rowAccount = try account(row.account)
            await container.activityLog.record(ActivityEntry(
                kind: row.kind,
                status: row.status,
                createdAt: now.addingTimeInterval(-row.minutesAgo * 60),
                accountID: rowAccount.id,
                accountName: rowAccount.name,
                bucket: row.bucket,
                key: row.key,
                byteCount: row.bytes,
                durationMS: row.durationMS,
                syncJobID: row.syncJob.flatMap { jobIDs[$0] },
                syncJobName: row.syncJob
            ))
        }

        // Metadata only: the key bytes would go to the Keychain, and the
        // Settings list never reads them.
        let context = ModelContext(container.encryptionContainer)
        for key in encryptionKeys {
            context.insert(BucketEncryptionKeyRecord(key: BucketEncryptionKey(
                label: key.label,
                accountID: try account(key.account).id,
                bucket: key.bucket,
                createdAt: now.addingTimeInterval(-key.daysAgo * 86_400)
            )))
        }
        try context.save()
        return created
    }
}
#endif
