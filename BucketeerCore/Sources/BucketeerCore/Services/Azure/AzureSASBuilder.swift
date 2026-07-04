//
//  AzureSASBuilder.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import CryptoKit

/// Builds a Service-SAS-signed URL for a single blob. Used by the
/// presigned-URL flow (Phase 9.9) so the user can hand a recipient an
/// anonymous-readable URL that expires after the chosen TTL without
/// surrendering the storage-account key.
///
/// Reference: Microsoft "Create a service SAS"
/// https://learn.microsoft.com/rest/api/storageservices/create-service-sas
///
/// Signing version pinned to **2021-12-02** to match the rest of the
/// Azure layer (`AzureSharedKeySigner.apiVersion`). The StringToSign
/// layout below is the v2020-12-06+ form (16 lines, trailing newlines
/// for empty fields).
struct AzureSASBuilder: Sendable {

    static let signingVersion = "2021-12-02"

    /// Service-SAS query parameters, ready to be appended to the blob
    /// URL. Names are the short form Azure expects (`sv`, `sp`, etc.).
    struct QueryParameters: Sendable {
        let signedVersion: String
        let signedResource: String     // "b" for blob
        let signedPermissions: String  // "r" for read
        let signedExpiry: String       // ISO-8601, UTC
        let signedProtocol: String     // "https"
        let signature: String          // base64 HMAC-SHA256
    }

    let accountName: String
    let accountKeyData: Data

    init?(accountName: String, base64AccountKey: String) {
        let trimmed = base64AccountKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountName.isEmpty,
              let decoded = Data(base64Encoded: trimmed)
        else { return nil }
        self.accountName = accountName
        self.accountKeyData = decoded
    }

    /// Generate a read-only SAS URL for a single blob that expires
    /// `ttl` seconds from now. Caller is responsible for clamping the
    /// TTL to whatever upper bound the UI permits.
    /// Clock-skew allowance: `signedStart` is backdated by this much so
    /// a client clock that runs ahead of Azure's servers cannot produce
    /// a SAS that is "not yet valid" — Microsoft recommends starting
    /// SAS validity ~15 minutes in the past for exactly this reason.
    /// The expiry is NOT padded; the user-chosen TTL stays the upper
    /// bound of the share window.
    static let clockSkewAllowance: TimeInterval = 10 * 60

    func presignedDownloadURL(
        baseURL: URL,
        container: String,
        blob: String,
        ttl: TimeInterval,
        now: Date = Date()
    ) -> URL? {
        let start = now.addingTimeInterval(-Self.clockSkewAllowance)
        let startString = Self.iso8601(start)
        let expiry = now.addingTimeInterval(ttl)
        let expiryString = Self.iso8601(expiry)

        let canonicalisedResource = "/blob/\(accountName)/\(container)/\(blob)"

        // StringToSign per Service SAS spec (signedVersion 2020-12-06+).
        // Each line is terminated with `\n`, including empties.
        let stringToSign = [
            "r",                          // signedPermissions
            startString,                  // signedStart
            expiryString,                 // signedExpiry
            canonicalisedResource,        // canonicalizedResource
            "",                           // signedIdentifier
            "",                           // signedIP
            "https",                      // signedProtocol
            Self.signingVersion,          // signedVersion
            "b",                          // signedResource
            "",                           // signedSnapshotTime
            "",                           // signedEncryptionScope
            "",                           // rscc (Cache-Control)
            "",                           // rscd (Content-Disposition)
            "",                           // rsce (Content-Encoding)
            "",                           // rscl (Content-Language)
            ""                            // rsct (Content-Type)
        ].joined(separator: "\n")

        let key = SymmetricKey(data: accountKeyData)
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(stringToSign.utf8),
            using: key
        )
        let signature = Data(mac).base64EncodedString()

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        // Replace the path: <base>/<container>/<blob>
        let encodedBlob = AzureRequestBuilder.percentEncode(blob: blob)
        components?.percentEncodedPath = "/\(container)/\(encodedBlob)"
        // Append SAS query items. Use URLQueryItem so the system
        // does the percent-encoding for us (the signature in
        // particular contains `+`, `/` and `=` which all need
        // escaping in a query).
        components?.queryItems = [
            URLQueryItem(name: "sv",  value: Self.signingVersion),
            URLQueryItem(name: "st",  value: startString),
            URLQueryItem(name: "sr",  value: "b"),
            URLQueryItem(name: "sp",  value: "r"),
            URLQueryItem(name: "se",  value: expiryString),
            URLQueryItem(name: "spr", value: "https"),
            URLQueryItem(name: "sig", value: signature)
        ]
        return components?.url
    }

    // MARK: - Helpers

    /// Azure SAS timestamps follow ISO-8601 in UTC: `2026-05-24T13:45:30Z`.
    /// Microsoft also accepts the sub-second-precision form; we use the
    /// integer-seconds form which matches every example in the docs.
    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
