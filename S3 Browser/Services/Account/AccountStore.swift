//
//  AccountStore.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation
import SwiftData

/// SwiftData-backed implementation of `AccountStoring`. Lives inside
/// the App Group container so the File Provider extension shares the
/// same store. Always returns Sendable `S3Account` snapshots; never
/// hands `S3AccountRecord` references to callers.
@ModelActor
actor AccountStore: AccountStoring {

    func all() async throws -> [S3Account] {
        do {
            let descriptor = FetchDescriptor<S3AccountRecord>(
                sortBy: [
                    SortDescriptor(\.sortIndex),
                    SortDescriptor(\.name)
                ]
            )
            return try modelContext.fetch(descriptor).map(\.snapshot)
        } catch {
            throw S3BrowserError.persistenceFailure(message: error.localizedDescription)
        }
    }

    func upsert(_ account: S3Account) async throws {
        do {
            let id = account.id
            let descriptor = FetchDescriptor<S3AccountRecord>(
                predicate: #Predicate { $0.id == id }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                existing.update(from: account)
            } else {
                let highestIndex = try modelContext.fetch(
                    FetchDescriptor<S3AccountRecord>(
                        sortBy: [SortDescriptor(\.sortIndex, order: .reverse)]
                    )
                ).first?.sortIndex ?? -1
                modelContext.insert(
                    S3AccountRecord(account: account, sortIndex: highestIndex + 1)
                )
            }
            try modelContext.save()
        } catch let error as S3BrowserError {
            throw error
        } catch {
            throw S3BrowserError.persistenceFailure(message: error.localizedDescription)
        }
    }

    func delete(id: UUID) async throws {
        do {
            let descriptor = FetchDescriptor<S3AccountRecord>(
                predicate: #Predicate { $0.id == id }
            )
            if let record = try modelContext.fetch(descriptor).first {
                modelContext.delete(record)
                try modelContext.save()
            }
        } catch {
            throw S3BrowserError.persistenceFailure(message: error.localizedDescription)
        }
    }

    func touchLastUsed(id: UUID) async throws {
        do {
            let descriptor = FetchDescriptor<S3AccountRecord>(
                predicate: #Predicate { $0.id == id }
            )
            if let record = try modelContext.fetch(descriptor).first {
                record.lastUsedAt = Date()
                try modelContext.save()
            }
        } catch {
            throw S3BrowserError.persistenceFailure(message: error.localizedDescription)
        }
    }
}
