//
//  BrowserViewModel.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation
import BucketeerCore

struct BreadcrumbCrumb: Hashable, Identifiable {
    var id: String { "\(bucket)/\(prefix)" }
    let label: String
    let bucket: String
    let prefix: String
}

@MainActor
@Observable
final class BrowserViewModel {
    /// Currently focused account. `nil` means no account selected yet.
    var account: S3Account?
    /// Currently focused bucket. `nil` means the content pane shows the
    /// list of buckets for `account`.
    var bucket: String?
    /// Always has a trailing slash (or is empty). Joined with `bucket`
    /// to form the listing scope.
    var prefix: String = ""
    var buckets: [S3Bucket] = []
    var objects: [S3Object] = []
    var continuationToken: String?
    var hasMore: Bool = false
    var isLoading: Bool = false
    var error: BucketeerError?
    var searchText: String = ""
    var selection: Set<String> = []

    var actionError: BucketeerError?
    var isPerformingAction: Bool = false

    private let s3Browser: any S3Browsing
    private let accountStore: any AccountStoring
    private let activityLog: (any ActivityLogging)?
    /// Phase 13.4 — captures a soft-delete copy + metadata before
    /// the actual delete fires.
    var trashCoordinator: TrashCoordinator?

    /// Monotonically increasing token incremented on every navigation
    /// or refresh. Each async load captures the value at issue time and
    /// only writes results back to state when the token still matches —
    /// fast A/B clicks therefore cannot land stale buckets or objects
    /// for the wrong location.
    private var requestGeneration: UInt64 = 0

    init(
        s3Browser: any S3Browsing,
        accountStore: any AccountStoring,
        activityLog: (any ActivityLogging)? = nil
    ) {
        self.s3Browser = s3Browser
        self.accountStore = accountStore
        self.activityLog = activityLog
    }

    /// Public accessor so the share sheet (and other future direct
    /// callers) can append to the audit log without us threading
    /// `activityLog` through three layers of constructors.
    var auditLog: (any ActivityLogging)? { activityLog }

    // MARK: - Derived

    var filteredObjects: [S3Object] {
        let needle = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return objects }
        return objects.filter { $0.displayName.lowercased().contains(needle) }
    }

    var breadcrumbs: [BreadcrumbCrumb] {
        guard let bucket else { return [] }
        var crumbs: [BreadcrumbCrumb] = [
            BreadcrumbCrumb(label: bucket, bucket: bucket, prefix: "")
        ]
        var cumulative = ""
        for part in prefix.split(separator: "/", omittingEmptySubsequences: true) {
            cumulative += String(part) + "/"
            crumbs.append(BreadcrumbCrumb(label: String(part), bucket: bucket, prefix: cumulative))
        }
        return crumbs
    }

    var canGoUp: Bool { !prefix.isEmpty }

    // MARK: - Navigation

    func clear() {
        bumpGeneration()
        account = nil
        bucket = nil
        prefix = ""
        buckets = []
        objects = []
        continuationToken = nil
        hasMore = false
        searchText = ""
        selection = []
        error = nil
    }

    func openAccount(_ account: S3Account) async {
        clear()
        self.account = account
        let token = bumpGeneration()
        await loadBuckets(token: token)
        try? await accountStore.touchLastUsed(id: account.id)
    }

    func openBucket(_ bucketName: String) async {
        self.bucket = bucketName
        self.prefix = ""
        self.selection = []
        self.searchText = ""
        let token = bumpGeneration()
        await loadObjects(reset: true, token: token)
    }

    func openFolder(_ folder: S3Object) async {
        guard folder.isFolder else { return }
        self.prefix = folder.key
        self.selection = []
        let token = bumpGeneration()
        await loadObjects(reset: true, token: token)
    }

    func navigate(to crumb: BreadcrumbCrumb) async {
        self.prefix = crumb.prefix
        self.selection = []
        let token = bumpGeneration()
        await loadObjects(reset: true, token: token)
    }

    func goUp() async {
        guard canGoUp else { return }
        let trimmed = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        let parent = parts.dropLast().joined(separator: "/")
        self.prefix = parent.isEmpty ? "" : parent + "/"
        self.selection = []
        let token = bumpGeneration()
        await loadObjects(reset: true, token: token)
    }

    // MARK: - Loading

    func refresh() async {
        let token = bumpGeneration()
        if bucket != nil {
            await loadObjects(reset: true, token: token)
        } else if account != nil {
            await loadBuckets(token: token)
        }
    }

    // MARK: - Object actions

    /// Deletes the listed keys. After completion the current listing
    /// is refreshed and any selection that referenced removed keys is
    /// cleared. The caller is responsible for confirming with the user
    /// first.
    func delete(keys: [String]) async {
        guard let account, let bucket, !keys.isEmpty else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        // Phase 13.4 — snapshot the objects into the soft-delete bin
        // BEFORE the provider delete so the cached copy is guaranteed
        // to be the pre-delete bytes. Best-effort; never block on it.
        if let trashCoordinator {
            await trashCoordinator.recordDeletion(
                account: account,
                bucket: bucket,
                keys: keys
            )
        }
        do {
            try await s3Browser.delete(account: account, bucket: bucket, keys: keys)
            selection.subtract(keys)
            actionError = nil
            for key in keys {
                await record(.delete, status: .success, key: key)
            }
            await loadObjectsResetting()
        } catch let error as BucketeerError {
            actionError = error
            for key in keys {
                await record(.delete, status: .failure, key: key, errorMessage: error.errorDescription)
            }
        } catch {
            actionError = .unknown(message: error.localizedDescription)
            for key in keys {
                await record(.delete, status: .failure, key: key, errorMessage: error.localizedDescription)
            }
        }
    }

    /// Rename = server-side copy + delete. Only safe for single keys
    /// (multi-rename has no S3 primitive). 5 GB cap on copy applies
    /// (see S3Service.copy).
    func rename(key: String, to newName: String) async {
        guard let account, let bucket else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            actionError = .unknown(
                message: String(
                    localized: "browser.action.rename.invalidName",
                    defaultValue: "Names cannot be empty or contain slashes."
                )
            )
            return
        }
        // Compose the new key by replacing the last path segment.
        let parent: String = {
            guard let lastSlash = key.lastIndex(of: "/") else { return "" }
            return String(key[..<key.index(after: lastSlash)])
        }()
        let newKey = parent + trimmed
        guard newKey != key else { return }

        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await s3Browser.copy(
                account: account,
                fromBucket: bucket,
                fromKey: key,
                toBucket: bucket,
                toKey: newKey,
                metadata: nil
            )
            try await s3Browser.delete(account: account, bucket: bucket, keys: [key])
            selection.remove(key)
            actionError = nil
            await record(
                .copy,
                status: .success,
                key: newKey,
                message: "Renamed from \(key)"
            )
            await loadObjectsResetting()
        } catch let error as BucketeerError {
            actionError = error
            await record(.copy, status: .failure, key: key, errorMessage: error.errorDescription)
        } catch {
            actionError = .unknown(message: error.localizedDescription)
            await record(.copy, status: .failure, key: key, errorMessage: error.localizedDescription)
        }
    }

    /// Creates a zero-byte folder marker at the current prefix.
    func createFolder(named name: String) async {
        guard let account, let bucket else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            actionError = .unknown(
                message: String(
                    localized: "browser.action.newFolder.invalidName",
                    defaultValue: "Folder names cannot be empty or contain slashes."
                )
            )
            return
        }
        let folderPrefix = prefix + trimmed + "/"
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await s3Browser.createFolder(
                account: account,
                bucket: bucket,
                prefix: folderPrefix
            )
            actionError = nil
            await record(.createFolder, status: .success, key: folderPrefix)
            await loadObjectsResetting()
        } catch let error as BucketeerError {
            actionError = error
            await record(.createFolder, status: .failure, key: folderPrefix, errorMessage: error.errorDescription)
        } catch {
            actionError = .unknown(message: error.localizedDescription)
            await record(.createFolder, status: .failure, key: folderPrefix, errorMessage: error.localizedDescription)
        }
    }

    // MARK: - Audit log

    private func record(
        _ kind: ActivityKind,
        status: ActivityStatus,
        key: String? = nil,
        message: String? = nil,
        errorMessage: String? = nil
    ) async {
        guard let activityLog, let account, let bucket else { return }
        let entry = ActivityEntry(
            kind: kind,
            status: status,
            accountID: account.id,
            accountName: account.name,
            bucket: bucket,
            key: key,
            message: message,
            errorMessage: errorMessage
        )
        await activityLog.record(entry)
    }

    func loadBuckets() async {
        let token = bumpGeneration()
        await loadBuckets(token: token)
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        // Pagination keeps the current generation — appending into the
        // same navigation context, not creating a new one.
        await loadObjects(reset: false, token: requestGeneration)
    }

    func loadObjectsResetting() async {
        let token = bumpGeneration()
        await loadObjects(reset: true, token: token)
    }

    // MARK: - Internals

    @discardableResult
    private func bumpGeneration() -> UInt64 {
        requestGeneration &+= 1
        return requestGeneration
    }

    private func isStale(_ token: UInt64) -> Bool {
        token != requestGeneration
    }

    private func loadBuckets(token: UInt64) async {
        guard let account else { return }
        isLoading = true
        // Codex medium #12: clear isLoading on every exit path,
        // including the stale-token short-circuits. Without this the
        // spinner stuck in the UI after rapid account switches.
        defer { if !isStale(token) { isLoading = false } }
        do {
            let result = try await s3Browser.listBuckets(account: account)
            guard !isStale(token), self.account?.id == account.id else { return }
            buckets = result
            error = nil
        } catch let error as BucketeerError {
            guard !isStale(token), self.account?.id == account.id else { return }
            self.error = error
            buckets = []
        } catch {
            guard !isStale(token), self.account?.id == account.id else { return }
            self.error = .unknown(message: error.localizedDescription)
            buckets = []
        }
    }

    private func loadObjects(reset: Bool, token: UInt64) async {
        guard let account, let bucket else { return }
        let prefixAtIssue = prefix
        if reset {
            objects = []
            continuationToken = nil
            hasMore = false
        }
        isLoading = true
        // Codex medium #12: defer-based isLoading clearing so the
        // spinner stops on every exit path, including the stale-token
        // returns that previously short-circuited before the final
        // `isLoading = false`.
        defer { if !isStale(token) { isLoading = false } }
        do {
            let page = try await s3Browser.listObjects(
                account: account,
                bucket: bucket,
                prefix: prefixAtIssue,
                continuationToken: reset ? nil : continuationToken
            )
            guard !isStale(token),
                  self.account?.id == account.id,
                  self.bucket == bucket,
                  self.prefix == prefixAtIssue
            else { return }
            if reset {
                objects = page.objects
            } else {
                objects.append(contentsOf: page.objects)
            }
            continuationToken = page.continuationToken
            hasMore = page.hasMore
            error = nil
        } catch let error as BucketeerError {
            guard !isStale(token),
                  self.account?.id == account.id,
                  self.bucket == bucket,
                  self.prefix == prefixAtIssue
            else { return }
            self.error = error
            if reset { objects = [] }
        } catch {
            guard !isStale(token),
                  self.account?.id == account.id,
                  self.bucket == bucket,
                  self.prefix == prefixAtIssue
            else { return }
            self.error = .unknown(message: error.localizedDescription)
            if reset { objects = [] }
        }
    }
}
