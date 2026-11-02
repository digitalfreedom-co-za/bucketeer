//
//  SharedStore.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation
import SwiftData

/// Single definition of the SwiftData store the host app and the File
/// Provider extension share through the App Group container.
///
/// Both processes must open the store with the identical schema:
/// a process that omits an entity would migrate the store and drop that
/// entity's rows. The host owns writes and migrations; the extension
/// opens the store with `allowsSave: false`.
public enum SharedStore {
    public static let configurationName = "Bucketeer"

    public static func makeSchema() -> Schema {
        Schema([S3AccountRecord.self, SyncJobRecord.self])
    }

    public static func makeContainer(url: URL, allowsSave: Bool) throws -> ModelContainer {
        let schema = makeSchema()
        let configuration = ModelConfiguration(
            configurationName,
            schema: schema,
            url: url,
            allowsSave: allowsSave
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Same schema, never written to disk — previews and tests.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = makeSchema()
        let configuration = ModelConfiguration(configurationName, schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
