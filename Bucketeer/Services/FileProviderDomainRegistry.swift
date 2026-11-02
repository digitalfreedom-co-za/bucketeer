//
//  FileProviderDomainRegistry.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation
import FileProvider

/// Seam over the static `NSFileProviderManager` domain calls, so the
/// ordering between mounting and turning on encryption can be tested
/// without registering real Finder domains.
@MainActor
protocol FileProviderDomainRegistry {
    func identifiers() async throws -> [NSFileProviderDomainIdentifier]
    func add(identifier: NSFileProviderDomainIdentifier, displayName: String) async throws
    func remove(identifier: NSFileProviderDomainIdentifier) async throws
    /// Asks the extension to report server-side changes of the domain.
    func signalWorkingSet(identifier: NSFileProviderDomainIdentifier) async throws
}

/// The real registry backed by `NSFileProviderManager`.
struct SystemFileProviderDomainRegistry: FileProviderDomainRegistry {
    func identifiers() async throws -> [NSFileProviderDomainIdentifier] {
        try await NSFileProviderManager.domains().map(\.identifier)
    }

    func add(identifier: NSFileProviderDomainIdentifier, displayName: String) async throws {
        try await NSFileProviderManager.add(NSFileProviderDomain(identifier: identifier, displayName: displayName))
    }

    /// No-op when no domain matches.
    func remove(identifier: NSFileProviderDomainIdentifier) async throws {
        let domains = try await NSFileProviderManager.domains()
        if let domain = domains.first(where: { $0.identifier == identifier }) {
            try await NSFileProviderManager.remove(domain)
        }
    }

    /// No-op when no domain matches.
    func signalWorkingSet(identifier: NSFileProviderDomainIdentifier) async throws {
        let domains = try await NSFileProviderManager.domains()
        guard let domain = domains.first(where: { $0.identifier == identifier }) else { return }
        try await NSFileProviderManager(for: domain)?.signalEnumerator(for: .workingSet)
    }
}
