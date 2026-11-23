//
//  CredentialLog.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 23.11.26.
//

import os

/// Diagnostics for credential persistence, shared by the host app and the
/// File Provider extension. Entries carry the event, the account UUID, an
/// OSStatus or error code and a fixed store location — never credential
/// values, endpoints, object keys or other personal data.
public enum CredentialLog {
    public static let logger = Logger(subsystem: AppEnvironment.keychainService, category: "credentials")
}
