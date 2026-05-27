//
//  AccountEntity.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import AppIntents
import BucketeerCore

/// AppIntent-facing wrapper for `S3Account`. Phase 13.12.
///
/// The intent runtime needs every parameter to be `Identifiable` +
/// `Codable` + `Sendable`; `S3Account` already is, but the entity
/// protocol layers Apple's `AppEntity` on top so Shortcuts can list
/// "all your Bucketeer accounts" in the parameter picker.
struct AccountEntity: AppEntity, Identifiable, Sendable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Account")
    }

    static let defaultQuery = AccountQuery()

    let id: UUID
    let name: String
    let providerName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(providerName)")
    }

    init(account: S3Account) {
        self.id = account.id
        self.name = account.name
        self.providerName = account.provider.displayName
    }
}

/// Provides Shortcuts with the live account list. Reads through the
/// shared `AppContainer` — when the App isn't running, the system
/// launches it (Shortcuts → "Open When Run" defaults to true on
/// macOS).
struct AccountQuery: EntityQuery, Sendable {
    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        let all = try await AppIntentsBridge.shared.accounts()
        let set = Set(identifiers)
        return all.filter { set.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AccountEntity] {
        try await AppIntentsBridge.shared.accounts()
    }
}
