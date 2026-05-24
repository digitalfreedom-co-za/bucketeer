//
//  ObjectVersionsViewModel.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import BucketeerCore

/// Drives the **Versions** sheet for a single object on a versioning-
/// enabled S3 bucket. Phase 13.6.
///
/// Wraps `S3Browsing.listVersions / restoreVersion / deleteVersion`.
/// On providers that don't expose object versions (Azure, MinIO
/// without versioning, etc.) the load surfaces a
/// `featureNotSupported` error that the view renders verbatim.
@MainActor
@Observable
final class ObjectVersionsViewModel {
    let account: S3Account
    let bucket: String
    let key: String

    var versions: [ObjectVersion] = []
    var isLoading: Bool = false
    var error: BucketeerError?
    /// Mirrors the row currently being acted on so the UI can show a
    /// per-row spinner.
    var inFlightVersionId: String?

    private let browser: any S3Browsing

    init(account: S3Account, bucket: String, key: String, browser: any S3Browsing) {
        self.account = account
        self.bucket = bucket
        self.key = key
        self.browser = browser
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            versions = try await browser.listVersions(
                account: account,
                bucket: bucket,
                key: key
            )
            error = nil
        } catch let bucketeerError as BucketeerError {
            versions = []
            error = bucketeerError
        } catch {
            versions = []
            self.error = .unknown(message: error.localizedDescription)
        }
    }

    func restore(_ version: ObjectVersion) async {
        inFlightVersionId = version.versionId
        defer { inFlightVersionId = nil }
        do {
            try await browser.restoreVersion(
                account: account,
                bucket: bucket,
                key: key,
                versionId: version.versionId
            )
            await reload()
        } catch let bucketeerError as BucketeerError {
            error = bucketeerError
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
    }

    func deleteVersion(_ version: ObjectVersion) async {
        inFlightVersionId = version.versionId
        defer { inFlightVersionId = nil }
        do {
            try await browser.deleteVersion(
                account: account,
                bucket: bucket,
                key: key,
                versionId: version.versionId
            )
            await reload()
        } catch let bucketeerError as BucketeerError {
            error = bucketeerError
        } catch {
            self.error = .unknown(message: error.localizedDescription)
        }
    }
}
