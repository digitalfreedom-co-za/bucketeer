//
//  AutoTagRuleStore.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import SwiftData

/// SwiftData-backed `AutoTagRuleStoring` implementation. Phase 13.8.
@ModelActor
public actor AutoTagRuleStore: AutoTagRuleStoring {

    public func all() async throws -> [AutoTagRule] {
        do {
            let descriptor = FetchDescriptor<AutoTagRuleRecord>(
                sortBy: [
                    SortDescriptor(\.sortIndex),
                    SortDescriptor(\.name)
                ]
            )
            return try modelContext.fetch(descriptor).map(\.snapshot)
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }

    public func upsert(_ rule: AutoTagRule) async throws {
        do {
            let id = rule.id
            let descriptor = FetchDescriptor<AutoTagRuleRecord>(
                predicate: #Predicate { $0.id == id }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                existing.update(from: rule)
            } else {
                let highest = try modelContext.fetch(
                    FetchDescriptor<AutoTagRuleRecord>(
                        sortBy: [SortDescriptor(\.sortIndex, order: .reverse)]
                    )
                ).first?.sortIndex ?? -1
                modelContext.insert(AutoTagRuleRecord(rule: rule, sortIndex: highest + 1))
            }
            try modelContext.save()
        } catch let error as BucketeerError {
            throw error
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }

    public func delete(id: UUID) async throws {
        do {
            let descriptor = FetchDescriptor<AutoTagRuleRecord>(
                predicate: #Predicate { $0.id == id }
            )
            if let record = try modelContext.fetch(descriptor).first {
                modelContext.delete(record)
                try modelContext.save()
            }
        } catch {
            throw BucketeerError.persistenceFailure(message: error.localizedDescription)
        }
    }
}
