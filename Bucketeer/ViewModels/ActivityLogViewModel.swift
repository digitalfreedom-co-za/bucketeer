//
//  ActivityLogViewModel.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import BucketeerCore

/// Drives the Activity Log window. Owns the visible-entries cache,
/// the filter selection, and the search field. Re-queries the
/// underlying `ActivityLogging` store whenever a filter changes via
/// `reload()`.
///
/// `reload()` is deliberately invoked from view callbacks (toolbar +
/// the SwiftUI `.onChange` modifiers in `ActivityLogView`) rather
/// than wired into an observable stream — the activity log is a
/// human-facing audit view, so polling on demand is enough and we
/// avoid the cost of pushing change notifications through SwiftData
/// for a list that the user only opens occasionally. Phase 13.1.
@MainActor
@Observable
final class ActivityLogViewModel {
    /// Hard cap on rows returned per query — the log can grow large
    /// over time and we never want to materialise the whole table.
    static let defaultLimit = 500

    var entries: [ActivityEntry] = []
    var totalCount: Int = 0
    var searchText: String = ""
    /// `nil` means "any account". When set, only entries for that
    /// account are returned.
    var accountFilter: UUID?
    /// Empty set means "any kind". Otherwise only entries of one of
    /// the listed kinds are returned.
    var kindFilter: Set<ActivityKind> = []
    var accounts: [S3Account] = []
    var isLoading: Bool = false
    var error: BucketeerError?

    private let activityLog: any ActivityLogging
    private let accountStore: any AccountStoring
    /// Reload generation — `.onChange`-driven reloads overlap when the
    /// user types quickly; only the newest run may publish results or
    /// clear the spinner, or an older run's rows land after (and
    /// mismatch) the filter the user actually sees.
    private var reloadGeneration = 0

    init(
        activityLog: any ActivityLogging,
        accountStore: any AccountStoring
    ) {
        self.activityLog = activityLog
        self.accountStore = accountStore
    }

    /// Re-issue the underlying query. Cheap enough to call on every
    /// filter change.
    func reload() async {
        reloadGeneration += 1
        let token = reloadGeneration
        isLoading = true
        defer {
            if token == reloadGeneration { isLoading = false }
        }
        do {
            let newEntries = try await activityLog.search(
                text: searchText.isEmpty ? nil : searchText,
                kinds: kindFilter.isEmpty ? nil : kindFilter,
                accountID: accountFilter,
                limit: Self.defaultLimit
            )
            let newTotal = try await activityLog.count()
            let newAccounts = try await accountStore.all()
            guard token == reloadGeneration else { return }
            entries = newEntries
            totalCount = newTotal
            accounts = newAccounts
            error = nil
        } catch let bucketeerError as BucketeerError {
            guard token == reloadGeneration else { return }
            error = bucketeerError
        } catch {
            guard token == reloadGeneration else { return }
            self.error = .unknown(message: error.localizedDescription)
        }
    }

    /// Wipe every entry from the store. UI calls this from a
    /// confirmation dialog.
    func deleteAll() async {
        do {
            try await activityLog.deleteAll()
            await reload()
        } catch let bucketeerError as BucketeerError {
            error = bucketeerError
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
    }

    /// CSV export of the currently visible entries. The CSV uses the
    /// RFC 4180 dialect (double-quote escaping, CRLF line endings) so
    /// Excel + Numbers open it without prompting for delimiter.
    func csvExport() -> String {
        let header = [
            "createdAt",
            "kind",
            "status",
            "account",
            "bucket",
            "key",
            "byteCount",
            "durationMS",
            "syncJob",
            "message",
            "errorMessage"
        ]
        let formatter = ISO8601DateFormatter()
        var lines: [String] = [header.joined(separator: ",")]
        for entry in entries {
            let cells: [String] = [
                formatter.string(from: entry.createdAt),
                entry.kind.rawValue,
                entry.status.rawValue,
                entry.accountName ?? "",
                entry.bucket ?? "",
                entry.key ?? "",
                entry.byteCount.map { String($0) } ?? "",
                entry.durationMS.map { String($0) } ?? "",
                entry.syncJobName ?? "",
                entry.message ?? "",
                entry.errorMessage ?? ""
            ]
            lines.append(cells.map(Self.escapeCSV).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// RFC 4180 quoting: wrap in double quotes and double-up embedded
    /// quotes whenever the cell contains a comma, quote, CR, or LF.
    private static func escapeCSV(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"") ||
            value.contains("\n") || value.contains("\r")
        guard needsQuoting else { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
