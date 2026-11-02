//
//  AzureSharedKeySigner.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import CryptoKit

/// Implements Azure Storage Shared Key signing as specified by Microsoft
/// (REST API 2021-12-02). Pure function over the request inputs; holds
/// no mutable state.
///
/// Algorithm:
/// 1. Build `StringToSign` from the verb, content headers, x-ms-headers
///    and canonicalised resource.
/// 2. HMAC-SHA256 with the base64-decoded account key.
/// 3. Base64-encode the MAC.
/// 4. Set `Authorization: SharedKey {accountName}:{signature}`.
///
/// References:
/// - https://learn.microsoft.com/rest/api/storageservices/authorize-with-shared-key
struct AzureSharedKeySigner: Sendable {

    /// The Azure REST API version sent with every request.
    static let apiVersion = "2021-12-02"

    /// Storage-account name (e.g. `myacct`). Goes into the `Authorization`
    /// header and the canonical resource prefix.
    let accountName: String

    /// Account key, base64-decoded. The Microsoft docs surface the key
    /// as a base64 string; we hold the raw bytes for HMAC efficiency.
    let accountKeyData: Data

    init?(accountName: String, base64AccountKey: String) {
        let trimmed = base64AccountKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountName.isEmpty,
              let decoded = Data(base64Encoded: trimmed)
        else { return nil }
        self.accountName = accountName
        self.accountKeyData = decoded
    }

    /// Sign the request **in place** — sets `x-ms-date`, `x-ms-version`
    /// and `Authorization` headers. Caller is expected to have already
    /// set any `x-ms-blob-type`, `Content-Type`, `Content-Length` and
    /// custom `x-ms-meta-*` headers before calling.
    func sign(_ request: inout URLRequest) {
        let dateValue = Self.rfc1123Now()
        request.setValue(dateValue, forHTTPHeaderField: "x-ms-date")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "x-ms-version")

        let stringToSign = buildStringToSign(for: request)
        let key = SymmetricKey(data: accountKeyData)
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(stringToSign.utf8),
            using: key
        )
        let signature = Data(mac).base64EncodedString()
        request.setValue(
            "SharedKey \(accountName):\(signature)",
            forHTTPHeaderField: "Authorization"
        )
    }

    // MARK: - StringToSign

    /// Builds the canonical StringToSign per the Shared Key spec. The
    /// header order is fixed — twelve newline-separated values, then the
    /// canonicalised headers, then the canonicalised resource.
    func buildStringToSign(for request: URLRequest) -> String {
        let method = request.httpMethod?.uppercased() ?? "GET"

        let headers = request.allHTTPHeaderFields ?? [:]
        let lookup = HeaderLookup(headers)

        // Content-Length: empty string for missing / zero / GET-style
        // requests. Microsoft's spec changed the convention in 2014 to
        // "empty if zero" — sending "0" is rejected as invalid.
        let contentLengthRaw = lookup["content-length"]
        let contentLength: String
        if let v = contentLengthRaw, v != "0" {
            contentLength = v
        } else {
            contentLength = ""
        }

        // Date is empty when x-ms-date is present (it always is for us).
        let dateValue = lookup["x-ms-date"] != nil ? "" : (lookup["date"] ?? "")

        let lines = [
            method,
            lookup["content-encoding"] ?? "",
            lookup["content-language"] ?? "",
            contentLength,
            lookup["content-md5"] ?? "",
            lookup["content-type"] ?? "",
            dateValue,
            lookup["if-modified-since"] ?? "",
            lookup["if-match"] ?? "",
            lookup["if-none-match"] ?? "",
            lookup["if-unmodified-since"] ?? "",
            lookup["range"] ?? ""
        ].joined(separator: "\n")

        let canonicalHeaders = Self.canonicalHeaders(headers)
        let canonicalResource = canonicalResource(for: request)

        var stringToSign = lines + "\n"
        if !canonicalHeaders.isEmpty {
            stringToSign += canonicalHeaders + "\n"
        }
        stringToSign += canonicalResource
        return stringToSign
    }

    /// Canonicalised x-ms-* headers: lowercase names, sorted, joined as
    /// `name:value\n`. Empty string if no x-ms-* headers were set.
    static func canonicalHeaders(_ headers: [String: String]) -> String {
        let entries = headers
            .map { (key: $0.key.lowercased(), value: trimWhitespace($0.value)) }
            .filter { $0.key.hasPrefix("x-ms-") }
            .sorted { $0.key < $1.key }
        guard !entries.isEmpty else { return "" }
        return entries
            .map { "\($0.key):\($0.value)" }
            .joined(separator: "\n")
    }

    /// Canonicalised resource — `/{account}/{path}` followed by sorted,
    /// lowercased query parameters. Each query parameter occupies its own
    /// line and uses the format `name:value[,value...]`. The whole block
    /// is the last line(s) of StringToSign.
    func canonicalResource(for request: URLRequest) -> String {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return "/\(accountName)/"
        }

        let path = components.percentEncodedPath.isEmpty
            ? "/"
            : components.percentEncodedPath
        var result = "/\(accountName)\(path)"

        // Group query items by lowercased name, sort the names, then
        // sort each name's value list. Decode percent-encoding so the
        // signature matches what Azure recomputes server-side.
        let items = components.queryItems ?? []
        guard !items.isEmpty else { return result }

        var grouped: [String: [String]] = [:]
        for item in items {
            let name = item.name.lowercased()
            let value = item.value?.removingPercentEncoding ?? item.value ?? ""
            grouped[name, default: []].append(value)
        }
        let sortedNames = grouped.keys.sorted()
        for name in sortedNames {
            let values = grouped[name, default: []].sorted()
            result += "\n\(name):\(values.joined(separator: ","))"
        }
        return result
    }

    // MARK: - Helpers

    /// RFC 1123 timestamp in GMT — Azure's required format for x-ms-date.
    static func rfc1123Now() -> String { rfc1123(Date()) }

    /// Stable formatter for testing.
    static func rfc1123(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }

    private static func trimWhitespace(_ value: String) -> String {
        // Microsoft normalises consecutive whitespace inside header
        // values to a single space; we only ever set headers we control,
        // so a basic trim is enough.
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Case-insensitive header lookup that returns the *first* value seen
/// when duplicates exist. URLRequest already deduplicates on assignment,
/// so this is mostly a safety net.
private struct HeaderLookup {
    private let storage: [String: String]
    init(_ headers: [String: String]) {
        var lowered: [String: String] = [:]
        for (k, v) in headers {
            let key = k.lowercased()
            if lowered[key] == nil {
                lowered[key] = v
            }
        }
        self.storage = lowered
    }
    subscript(key: String) -> String? { storage[key.lowercased()] }
}
