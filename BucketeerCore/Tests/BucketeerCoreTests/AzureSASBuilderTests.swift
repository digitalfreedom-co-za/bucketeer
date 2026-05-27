//
//  AzureSASBuilderTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// Verifies that the Service-SAS URL we generate (Phase 9.9) is shaped
/// the way Azure expects: every required query parameter present, signed
/// version pinned to the same value as the request signer, signature
/// computed against the v2020-12-06+ StringToSign layout.
@Suite("AzureSASBuilder")
struct AzureSASBuilderTests {

    /// Test account / key — never used against a real endpoint.
    private let builder = AzureSASBuilder(
        accountName: "myaccount",
        base64AccountKey: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    )!

    private let baseURL = URL(string: "https://myaccount.blob.core.windows.net")!

    @Test("Initialiser rejects invalid base64")
    func initialiserRejectsBadKey() {
        let bad = AzureSASBuilder(
            accountName: "myaccount",
            base64AccountKey: "spaces are not valid base64"
        )
        #expect(bad == nil)
    }

    @Test("Initialiser rejects empty account name")
    func initialiserRejectsEmptyName() {
        let bad = AzureSASBuilder(
            accountName: "",
            base64AccountKey: "AAAA"
        )
        #expect(bad == nil)
    }

    @Test("Generated URL has every required SAS query parameter")
    func generatedURLHasAllParams() {
        let url = builder.presignedDownloadURL(
            baseURL: baseURL,
            container: "photos",
            blob: "2026/may/img.jpg",
            ttl: 3600,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(url != nil)
        guard let url = url else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        #expect(items["sv"] == AzureSASBuilder.signingVersion)
        #expect(items["sr"] == "b")
        #expect(items["sp"] == "r")
        #expect(items["spr"] == "https")
        #expect(items["se"]?.hasSuffix("Z") == true)
        #expect((items["sig"]?.count ?? 0) > 0)
    }

    @Test("Path preserves the virtual folder slash structure")
    func pathPreservesSlashes() {
        let url = builder.presignedDownloadURL(
            baseURL: baseURL,
            container: "photos",
            blob: "subdir/file.jpg",
            ttl: 600
        )
        #expect(url?.path == "/photos/subdir/file.jpg")
    }

    @Test("Blob names with reserved characters are percent-encoded")
    func reservedCharactersEncoded() {
        let url = builder.presignedDownloadURL(
            baseURL: baseURL,
            container: "c",
            blob: "folder/file name?#.txt",
            ttl: 60
        )
        // Slash kept; space + ? + # encoded inside the path component
        #expect(url?.absoluteString.contains("/c/folder/file%20name%3F%23.txt") == true)
    }

    @Test("Signature is deterministic for fixed inputs")
    func signatureDeterministic() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let url1 = builder.presignedDownloadURL(
            baseURL: baseURL,
            container: "c",
            blob: "blob.bin",
            ttl: 3600,
            now: now
        )!
        let url2 = builder.presignedDownloadURL(
            baseURL: baseURL,
            container: "c",
            blob: "blob.bin",
            ttl: 3600,
            now: now
        )!
        #expect(url1 == url2)
    }

    @Test("Different TTLs produce different signatures")
    func signatureChangesWithTTL() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let oneHour = builder.presignedDownloadURL(
            baseURL: baseURL, container: "c", blob: "blob.bin",
            ttl: 3600, now: now
        )!
        let oneDay = builder.presignedDownloadURL(
            baseURL: baseURL, container: "c", blob: "blob.bin",
            ttl: 86_400, now: now
        )!
        let sig1 = URLComponents(url: oneHour, resolvingAgainstBaseURL: false)!
            .queryItems?.first(where: { $0.name == "sig" })?.value
        let sig2 = URLComponents(url: oneDay, resolvingAgainstBaseURL: false)!
            .queryItems?.first(where: { $0.name == "sig" })?.value
        #expect(sig1 != sig2)
    }

    @Test("iso8601 formatter outputs a Z-suffixed UTC stamp")
    func iso8601() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let formatted = AzureSASBuilder.iso8601(date)
        #expect(formatted.hasSuffix("Z"))
        #expect(formatted.contains("T"))
    }
}
