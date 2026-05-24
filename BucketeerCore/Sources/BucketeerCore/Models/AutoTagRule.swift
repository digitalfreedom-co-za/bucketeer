//
//  AutoTagRule.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation

/// One auto-tagging rule. Phase 13.8. The user authors these in
/// Settings → Rules; the upload pipeline evaluates every enabled rule
/// against each successfully-uploaded object and applies the union of
/// the matching rules' tag + user-metadata maps.
///
/// Both `filenameGlob` and `mimePrefix` may be empty:
/// - empty `filenameGlob` ⇒ match any filename
/// - empty `mimePrefix` ⇒ match any MIME type
/// A rule with both fields empty matches every upload — that's
/// intentional ("default tags for everything"), but the editor
/// surfaces a hint so the user knows.
public struct AutoTagRule: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var enabled: Bool
    public var filenameGlob: String
    public var mimePrefix: String
    public var tags: [String: String]
    public var userMetadata: [String: String]

    public init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = true,
        filenameGlob: String = "",
        mimePrefix: String = "",
        tags: [String: String] = [:],
        userMetadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.filenameGlob = filenameGlob
        self.mimePrefix = mimePrefix
        self.tags = tags
        self.userMetadata = userMetadata
    }
}
