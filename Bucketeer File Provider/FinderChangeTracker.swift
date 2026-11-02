//
//  FinderChangeTracker.swift
//  Bucketeer File Provider
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation
import BucketeerCore

extension FinderChangeTracker {
    /// One tracker per extension process. The state lives in the
    /// extension's own Application Support folder; when that folder is
    /// unavailable the temporary folder is used, which only costs a
    /// re-enumeration once it is cleared.
    static let shared = FinderChangeTracker(storageDirectory: (
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    ).appending(path: "ChangeTracking", directoryHint: .isDirectory))
}
