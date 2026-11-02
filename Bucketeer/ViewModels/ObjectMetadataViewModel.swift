//
//  ObjectMetadataViewModel.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import BucketeerCore

/// Drives the metadata + tags editor sheet. Phase 13.7.
///
/// Loads the editable bits via `S3Browsing.loadMetadata`, holds a
/// mutable copy the view binds to, and persists with
/// `saveMetadata`. The provider's transactional guarantees decide
/// whether the change is atomic (S3 splits metadata vs tags into two
/// RPCs — the second can fail after the first succeeded).
@MainActor
@Observable
final class ObjectMetadataViewModel {
    let account: S3Account
    let bucket: String
    let key: String

    var metadata: ObjectMetadata = ObjectMetadata()
    /// Snapshot taken at load time; used to decide whether Save is
    /// actually a no-op (and to colour the Save button).
    var original: ObjectMetadata = ObjectMetadata()
    var isLoading: Bool = false
    var isSaving: Bool = false
    var error: BucketeerError?
    var didSaveSuccessfully: Bool = false

    private let browser: any S3Browsing

    init(account: S3Account, bucket: String, key: String, browser: any S3Browsing) {
        self.account = account
        self.bucket = bucket
        self.key = key
        self.browser = browser
    }

    var hasChanges: Bool { metadata != original }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await browser.loadMetadata(
                account: account, bucket: bucket, key: key
            )
            metadata = loaded
            original = loaded
            error = nil
        } catch let bucketeerError as BucketeerError {
            error = bucketeerError
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
    }

    func save() async {
        guard hasChanges, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await browser.saveMetadata(
                account: account,
                bucket: bucket,
                key: key,
                metadata: metadata
            )
            original = metadata
            error = nil
            didSaveSuccessfully = true
        } catch let bucketeerError as BucketeerError {
            error = bucketeerError
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
    }
}
