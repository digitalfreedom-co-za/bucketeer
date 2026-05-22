//
//  BrowserViewModel.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation

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
    var error: S3BrowserError?
    var searchText: String = ""
    var selection: Set<String> = []

    private let s3Browser: S3Browsing
    private let accountStore: AccountStoring

    /// Monotonically increasing token incremented on every navigation
    /// or refresh. Each async load captures the value at issue time and
    /// only writes results back to state when the token still matches —
    /// fast A/B clicks therefore cannot land stale buckets or objects
    /// for the wrong location.
    private var requestGeneration: UInt64 = 0

    init(s3Browser: S3Browsing, accountStore: AccountStoring) {
        self.s3Browser = s3Browser
        self.accountStore = accountStore
    }

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
        do {
            let result = try await s3Browser.listBuckets(account: account)
            guard !isStale(token), self.account?.id == account.id else { return }
            buckets = result
            error = nil
        } catch let error as S3BrowserError {
            guard !isStale(token), self.account?.id == account.id else { return }
            self.error = error
            buckets = []
        } catch {
            guard !isStale(token), self.account?.id == account.id else { return }
            self.error = .unknown(message: error.localizedDescription)
            buckets = []
        }
        if !isStale(token) { isLoading = false }
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
        } catch let error as S3BrowserError {
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
        if !isStale(token) { isLoading = false }
    }
}
