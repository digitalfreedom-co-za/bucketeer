//
//  BucketeerError.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation

/// Domain errors surfaced from services up to view models. Service code
/// must translate Soto / network / Keychain errors into one of these
/// cases before the value crosses the actor boundary into the UI.
public enum BucketeerError: Error, Sendable, Equatable {
    case authenticationFailed
    /// The Keychain holds no credentials for the account.
    case credentialsMissing
    /// The provider does not know the access key (`InvalidAccessKeyId`).
    /// Civo keys only exist in the region they were created in, so
    /// there it usually means a region mismatch.
    case accessKeyNotRecognized(provider: S3Provider?, region: String?)
    /// The secret key does not belong to the access key
    /// (`SignatureDoesNotMatch`).
    case secretKeyMismatch
    /// The key may not call ListBuckets; it needs a bucket name.
    case bucketListingDenied
    case bucketNotFound(String)
    case objectNotFound(key: String)
    case networkUnavailable
    case providerError(statusCode: Int, message: String)
    case sandboxAccessDenied(URL)
    case keychainFailure(status: Int32)
    case persistenceFailure(message: String)
    case cancelled
    /// The current provider doesn't expose the requested feature
    /// (e.g. asking Azure Blob Storage for S3-style object versions).
    /// Phase 13.6.
    case featureNotSupported(featureKey: String)
    /// A conditional write (If-Match) was refused because the object
    /// changed on the server (HTTP 412).
    case preconditionFailed(key: String)
    /// The object needs a copy in parts that this provider cannot pin
    /// to one version, so it is not copied at all.
    case largeCopyUnsupported(key: String)
    /// `message` is shown as-is, so it must already be user-facing text.
    case unknown(message: String)
}

extension BucketeerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return String(localized: "error.authenticationFailed",
                          defaultValue: "Authentication failed.")
        case .credentialsMissing:
            return String(localized: "error.credentialsMissing",
                          defaultValue: "The credentials for this account are missing. Edit the account and enter the access key and secret key again.")
        case .accessKeyNotRecognized(let provider, let region):
            guard let region, !region.isEmpty else {
                return String(localized: "error.accessKeyNotRecognized",
                              defaultValue: "The access key is not recognized in this region. Check the access key and the region.")
            }
            if provider == .civo {
                return String(localized: "error.accessKeyNotRecognized.civo",
                              defaultValue: "Civo does not recognize this access key in region \(region). Civo keys only work in the region they were created in — check the region in the account settings.")
            }
            return String(localized: "error.accessKeyNotRecognized.region",
                          defaultValue: "The access key is not recognized in region \(region). Check the access key and the region.")
        case .secretKeyMismatch:
            return String(localized: "error.secretKeyMismatch",
                          defaultValue: "The secret key does not match the access key. Enter the secret key again.")
        case .bucketListingDenied:
            return String(localized: "error.bucketListingDenied",
                          defaultValue: "This key can't list buckets. Edit the account and enter the bucket name.")
        case .bucketNotFound(let name):
            return String(localized: "error.bucketNotFound",
                          defaultValue: "Bucket \"\(name)\" was not found.")
        case .objectNotFound(let key):
            return String(localized: "error.objectNotFound",
                          defaultValue: "Object \"\(key)\" was not found.")
        case .networkUnavailable:
            return String(localized: "error.networkUnavailable",
                          defaultValue: "Network unavailable.")
        case .providerError(let code, let message):
            return String(localized: "error.providerError",
                          defaultValue: "Provider returned \(code): \(message)")
        case .sandboxAccessDenied(let url):
            return String(localized: "error.sandboxAccessDenied",
                          defaultValue: "Cannot access \(url.path) — the app sandbox denied the request.")
        case .keychainFailure(let status):
            // As text: an OSStatus is a code, not a quantity, so no
            // locale grouping ("-25.308").
            return String(localized: "error.keychainFailure",
                          defaultValue: "Keychain operation failed (status \(String(status))).")
        case .persistenceFailure(let message):
            return String(localized: "error.persistenceFailure",
                          defaultValue: "Saving to the local store failed: \(message)")
        case .cancelled:
            return String(localized: "error.cancelled",
                          defaultValue: "The operation was cancelled.")
        case .featureNotSupported(let featureKey):
            return String(localized: "error.featureNotSupported",
                          defaultValue: "This provider does not support \(featureKey).")
        case .preconditionFailed(let key):
            return String(localized: "error.preconditionFailed",
                          defaultValue: "\"\(key)\" was changed on the server in the meantime.")
        case .largeCopyUnsupported(let key):
            return String(localized: "error.largeCopyUnsupported",
                          defaultValue: "\"\(key)\" is too large for this provider to copy on the server without risking a mix of two versions. Download it and upload it again instead.")
        case .unknown(let message):
            // Call sites pass either an already-localized explanation or
            // a system `localizedDescription`; wrapping it in a catalog
            // entry used to drop the message (the entry had no `%@`).
            return message
        }
    }
}
