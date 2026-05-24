//
//  TrashViewModel.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import BucketeerCore

/// Drives the **Trash** window. Owns the visible-entries cache and
/// the in-flight restore/forget operations. Phase 13.4.
///
/// Like `ActivityLogViewModel`, this is a polling view-model rather
/// than a streaming one — the trash is opened occasionally, not
/// watched continuously, and re-querying on demand keeps the
/// SwiftData layer simple.
@MainActor
@Observable
final class TrashViewModel {
    static let defaultLimit = 500

    var items: [TrashedItem] = []
    var totalCount: Int = 0
    var accounts: [S3Account] = []
    var isLoading: Bool = false
    var error: BucketeerError?
    var actionError: String?

    private let trashStore: any TrashStoring
    private let coordinator: TrashCoordinator
    private let accountStore: any AccountStoring

    init(
        trashStore: any TrashStoring,
        coordinator: TrashCoordinator,
        accountStore: any AccountStoring
    ) {
        self.trashStore = trashStore
        self.coordinator = coordinator
        self.accountStore = accountStore
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await trashStore.recent(limit: Self.defaultLimit)
            totalCount = try await trashStore.count()
            accounts = try await accountStore.all()
            error = nil
        } catch let bucketeerError as BucketeerError {
            error = bucketeerError
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
    }

    func restore(_ item: TrashedItem) async {
        guard let account = accounts.first(where: { $0.id == item.accountID }) else {
            actionError = String(
                localized: "trash.error.accountGone",
                defaultValue: "The original account is no longer connected."
            )
            return
        }
        if let message = await coordinator.restore(item: item, account: account) {
            actionError = message
        } else {
            actionError = nil
            await reload()
        }
    }

    func forget(_ item: TrashedItem) async {
        if let message = await coordinator.forget(item: item) {
            actionError = message
        } else {
            actionError = nil
            await reload()
        }
    }

    func empty() async {
        if let message = await coordinator.empty() {
            actionError = message
        } else {
            actionError = nil
            await reload()
        }
    }
}
