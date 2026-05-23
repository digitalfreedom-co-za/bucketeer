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
    case bucketNotFound(String)
    case objectNotFound(key: String)
    case networkUnavailable
    case providerError(statusCode: Int, message: String)
    case sandboxAccessDenied(URL)
    case keychainFailure(status: Int32)
    case persistenceFailure(message: String)
    case cancelled
    case unknown(message: String)
}

extension BucketeerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return String(localized: "error.authenticationFailed",
                          defaultValue: "Authentication failed.")
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
            return String(localized: "error.keychainFailure",
                          defaultValue: "Keychain operation failed (status \(status)).")
        case .persistenceFailure(let message):
            return String(localized: "error.persistenceFailure",
                          defaultValue: "Saving to the local store failed: \(message)")
        case .cancelled:
            return String(localized: "error.cancelled",
                          defaultValue: "The operation was cancelled.")
        case .unknown(let message):
            return String(localized: "error.unknown",
                          defaultValue: "Unexpected error: \(message)")
        }
    }
}
