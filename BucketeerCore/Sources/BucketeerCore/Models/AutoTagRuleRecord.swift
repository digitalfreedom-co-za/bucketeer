//
//  AutoTagRuleRecord.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import SwiftData

/// SwiftData persistence for an `AutoTagRule`. Phase 13.8. Stored in
/// the host-only activity / trash neighbouring containers — see
/// `AppContainer.makeAutoTagContainer`.
///
/// Tag + metadata maps are persisted as JSON `Data` blobs so the
/// schema doesn't have to grow per-entry rows for a relationship that
/// is always read together with its parent.
@Model
public final class AutoTagRuleRecord {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var enabled: Bool
    public var filenameGlob: String
    public var mimePrefix: String
    public var tagsData: Data
    public var userMetadataData: Data
    public var sortIndex: Int

    public init(rule: AutoTagRule, sortIndex: Int = 0) {
        self.id = rule.id
        self.name = rule.name
        self.enabled = rule.enabled
        self.filenameGlob = rule.filenameGlob
        self.mimePrefix = rule.mimePrefix
        let encoder = JSONEncoder()
        self.tagsData = (try? encoder.encode(rule.tags)) ?? Data()
        self.userMetadataData = (try? encoder.encode(rule.userMetadata)) ?? Data()
        self.sortIndex = sortIndex
    }

    public func update(from rule: AutoTagRule) {
        self.name = rule.name
        self.enabled = rule.enabled
        self.filenameGlob = rule.filenameGlob
        self.mimePrefix = rule.mimePrefix
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(rule.tags) { self.tagsData = data }
        if let data = try? encoder.encode(rule.userMetadata) { self.userMetadataData = data }
    }

    public var snapshot: AutoTagRule {
        let decoder = JSONDecoder()
        let tags = (try? decoder.decode([String: String].self, from: tagsData)) ?? [:]
        let metadata = (try? decoder.decode([String: String].self, from: userMetadataData)) ?? [:]
        return AutoTagRule(
            id: id,
            name: name,
            enabled: enabled,
            filenameGlob: filenameGlob,
            mimePrefix: mimePrefix,
            tags: tags,
            userMetadata: metadata
        )
    }
}
