//
//  AutoTagRulesViewModel.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import BucketeerCore

/// Drives the Settings → Rules tab for auto-tagging. Phase 13.8.
@MainActor
@Observable
final class AutoTagRulesViewModel {
    var rules: [AutoTagRule] = []
    var error: BucketeerError?

    private let store: any AutoTagRuleStoring
    private let coordinator: AutoTagCoordinator

    init(store: any AutoTagRuleStoring, coordinator: AutoTagCoordinator) {
        self.store = store
        self.coordinator = coordinator
    }

    func reload() async {
        do {
            rules = try await store.all()
            error = nil
        } catch let bucketeerError as BucketeerError {
            error = bucketeerError
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
    }

    func save(_ rule: AutoTagRule) async {
        do {
            try await store.upsert(rule)
            await reload()
            await coordinator.reload()
        } catch let bucketeerError as BucketeerError {
            error = bucketeerError
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
    }

    func delete(_ rule: AutoTagRule) async {
        do {
            try await store.delete(id: rule.id)
            await reload()
            await coordinator.reload()
        } catch let bucketeerError as BucketeerError {
            error = bucketeerError
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
    }
}
