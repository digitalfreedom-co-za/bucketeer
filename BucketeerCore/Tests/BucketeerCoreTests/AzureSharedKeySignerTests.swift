//
//  AzureSharedKeySignerTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// Verifies the Shared Key signer's StringToSign construction and the
/// canonicalisation helpers against worked examples derived from
/// Microsoft's authorize-with-shared-key reference. Catching regressions
/// here is critical — a wrong signature means every Azure request gets
/// a 403 and user data becomes unreachable.
@Suite("AzureSharedKeySigner")
struct AzureSharedKeySignerTests {

    /// Fixed test account / key — never used against a real endpoint.
    /// Key is a valid base64-encoded 64-byte secret so the signer can
    /// decode it without failing the initialiser.
    private let signer = AzureSharedKeySigner(
        accountName: "myaccount",
        base64AccountKey: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    )!

    @Test("Initialiser rejects invalid base64 keys")
    func initialiserRejectsBadKey() {
        let bad = AzureSharedKeySigner(
            accountName: "myaccount",
            base64AccountKey: "not base64 because of the spaces"
        )
        #expect(bad == nil)
    }

    @Test("Initialiser rejects empty account name")
    func initialiserRejectsEmptyName() {
        let bad = AzureSharedKeySigner(
            accountName: "",
            base64AccountKey: "AAAA"
        )
        #expect(bad == nil)
    }

    @Test("Canonical headers sort x-ms-* keys alphabetically and skip non-x-ms")
    func canonicalHeadersSort() {
        let headers: [String: String] = [
            "x-ms-version": "2021-12-02",
            "x-ms-date":    "Sun, 24 May 2026 12:34:56 GMT",
            "x-ms-blob-type": "BlockBlob",
            "Content-Type": "application/octet-stream",
            "Authorization": "should-be-stripped"
        ]
        let canonical = AzureSharedKeySigner.canonicalHeaders(headers)
        let lines = canonical.split(separator: "\n").map(String.init)
        #expect(lines == [
            "x-ms-blob-type:BlockBlob",
            "x-ms-date:Sun, 24 May 2026 12:34:56 GMT",
            "x-ms-version:2021-12-02"
        ])
    }

    @Test("Canonical headers returns empty string when no x-ms-* headers exist")
    func canonicalHeadersEmpty() {
        let canonical = AzureSharedKeySigner.canonicalHeaders([
            "Content-Type": "text/plain"
        ])
        #expect(canonical.isEmpty)
    }

    @Test("Canonical resource builds /<account>/<path> with sorted lowercased query params")
    func canonicalResourceBuilds() {
        var request = URLRequest(
            url: URL(string: "https://myaccount.blob.core.windows.net/container?restype=container&comp=list&prefix=photos%2F2026%2F")!
        )
        request.httpMethod = "GET"
        let resource = signer.canonicalResource(for: request)
        let expected = """
        /myaccount/container
        comp:list
        prefix:photos/2026/
        restype:container
        """
        #expect(resource == expected)
    }

    @Test("Canonical resource handles repeated query parameters")
    func canonicalResourceMultiValue() {
        var components = URLComponents(string: "https://myaccount.blob.core.windows.net/cont")!
        components.queryItems = [
            URLQueryItem(name: "tag", value: "b"),
            URLQueryItem(name: "tag", value: "a")
        ]
        let request = URLRequest(url: components.url!)
        let resource = signer.canonicalResource(for: request)
        #expect(resource == "/myaccount/cont\ntag:a,b")
    }

    @Test("StringToSign uses empty Date when x-ms-date is set, empty Content-Length for GET")
    func stringToSignForGet() {
        var request = URLRequest(
            url: URL(string: "https://myaccount.blob.core.windows.net/cont?comp=list&restype=container")!
        )
        request.httpMethod = "GET"
        request.setValue("Sun, 24 May 2026 12:34:56 GMT", forHTTPHeaderField: "x-ms-date")
        request.setValue("2021-12-02", forHTTPHeaderField: "x-ms-version")
        let stringToSign = signer.buildStringToSign(for: request)
        let lines = stringToSign.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Verb + 11 empty content-related lines + canonical headers + canonical resource
        #expect(lines[0] == "GET")
        // Content-Length empty (no body, no header)
        #expect(lines[3] == "")
        // Date line empty because x-ms-date is present
        #expect(lines[6] == "")
        // Canonical headers right after the 12 fixed lines
        #expect(lines[12] == "x-ms-date:Sun, 24 May 2026 12:34:56 GMT")
        #expect(lines[13] == "x-ms-version:2021-12-02")
        // Canonical resource at the end
        #expect(lines[14] == "/myaccount/cont")
        #expect(lines.last == "restype:container")
    }

    @Test("StringToSign uses Content-Length value for non-empty body")
    func stringToSignForPutBlock() {
        var request = URLRequest(
            url: URL(string: "https://myaccount.blob.core.windows.net/cont/blob?comp=block&blockid=YWJj")!
        )
        request.httpMethod = "PUT"
        request.setValue("Sun, 24 May 2026 12:34:56 GMT", forHTTPHeaderField: "x-ms-date")
        request.setValue("2021-12-02", forHTTPHeaderField: "x-ms-version")
        request.setValue("8388608", forHTTPHeaderField: "Content-Length")
        let stringToSign = signer.buildStringToSign(for: request)
        let lines = stringToSign.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines[0] == "PUT")
        #expect(lines[3] == "8388608")
    }

    @Test("sign(_:) sets Authorization, x-ms-date and x-ms-version headers")
    func signSetsRequiredHeaders() {
        var request = URLRequest(
            url: URL(string: "https://myaccount.blob.core.windows.net/cont?comp=list&restype=container")!
        )
        request.httpMethod = "GET"
        signer.sign(&request)
        #expect(request.value(forHTTPHeaderField: "x-ms-date") != nil)
        #expect(request.value(forHTTPHeaderField: "x-ms-version") == AzureSharedKeySigner.apiVersion)
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("SharedKey myaccount:") ?? false)
    }
}
