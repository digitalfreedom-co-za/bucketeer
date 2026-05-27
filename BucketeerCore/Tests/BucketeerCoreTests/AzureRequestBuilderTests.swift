//
//  AzureRequestBuilderTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import Testing
@testable import BucketeerCore

@Suite("AzureRequestBuilder")
struct AzureRequestBuilderTests {

    private func account(
        accountName: String = "myaccount",
        endpointOverride: URL? = nil
    ) -> S3Account {
        S3Account(
            id: UUID(),
            name: "Test",
            provider: .azureBlob,
            region: "auto",
            endpointOverride: endpointOverride,
            accountID: accountName
        )
    }

    @Test("Default base URL derives from the storage account name")
    func defaultBaseURL() {
        let builder = AzureRequestBuilder(account: account())
        let url = builder.listContainersURL()
        #expect(url.absoluteString == "https://myaccount.blob.core.windows.net/?comp=list")
    }

    @Test("Sovereign-cloud endpoint override is used verbatim")
    func sovereignOverride() {
        let override = URL(string: "https://myaccount.blob.core.usgovcloudapi.net")!
        let builder = AzureRequestBuilder(account: account(endpointOverride: override))
        let url = builder.listContainersURL()
        #expect(url.absoluteString == "https://myaccount.blob.core.usgovcloudapi.net/?comp=list")
    }

    @Test("listBlobsURL composes restype/comp/delimiter/prefix/marker")
    func listBlobsURL() {
        let builder = AzureRequestBuilder(account: account())
        let url = builder.listBlobsURL(container: "photos", prefix: "2026/", marker: "page-2")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        #expect(components.path == "/photos")
        #expect(items["restype"] == "container")
        #expect(items["comp"] == "list")
        #expect(items["delimiter"] == "/")
        #expect(items["prefix"] == "2026/")
        #expect(items["marker"] == "page-2")
    }

    @Test("listBlobsURL omits prefix/marker when empty")
    func listBlobsURLMinimal() {
        let builder = AzureRequestBuilder(account: account())
        let url = builder.listBlobsURL(container: "photos", prefix: "", marker: nil)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = (components.queryItems ?? []).map(\.name)
        #expect(!items.contains("prefix"))
        #expect(!items.contains("marker"))
        #expect(items.contains("restype"))
        #expect(items.contains("comp"))
        #expect(items.contains("delimiter"))
    }

    @Test("blobURL preserves forward slashes in keys (virtual folders)")
    func blobURLPreservesSlashes() {
        let builder = AzureRequestBuilder(account: account())
        let url = builder.blobURL(container: "photos", blob: "2026/may/photo.jpg")
        // The slash is preserved; spaces / question marks etc. would be
        // percent-encoded by `percentEncode(blob:)`.
        #expect(url.path == "/photos/2026/may/photo.jpg")
    }

    @Test("blobURL percent-encodes spaces and reserved characters")
    func blobURLEncodesReservedCharacters() {
        let builder = AzureRequestBuilder(account: account())
        let url = builder.blobURL(container: "c", blob: "folder/file name?#.txt")
        // Forward slash kept; space + ? + # encoded.
        #expect(url.absoluteString.contains("/folder/file%20name%3F%23.txt"))
    }

    @Test("putBlockURL adds comp + blockid query params")
    func putBlockURL() {
        let builder = AzureRequestBuilder(account: account())
        let url = builder.putBlockURL(container: "c", blob: "blob.bin", blockID: "YWJj")
        let items = Dictionary(
            uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        #expect(items["comp"] == "block")
        #expect(items["blockid"] == "YWJj")
    }

    @Test("blockListXML body wraps every block ID in a <Latest> element")
    func blockListXML() {
        let ids = [AzureRequestBuilder.blockID(index: 0),
                   AzureRequestBuilder.blockID(index: 1),
                   AzureRequestBuilder.blockID(index: 99)]
        let body = AzureRequestBuilder.blockListXML(blockIDs: ids)
        let xml = String(decoding: body, as: UTF8.self)
        #expect(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<BlockList>"))
        #expect(xml.hasSuffix("</BlockList>"))
        for id in ids {
            #expect(xml.contains("<Latest>\(id)</Latest>"))
        }
    }

    @Test("blockID is base64-encoded and same length for any index — required by Azure")
    func blockIDsAreSameLength() {
        let lengths = (0..<10_000).map { AzureRequestBuilder.blockID(index: $0).count }
        // All entries identical → set has exactly one element
        #expect(Set(lengths).count == 1)
        // Must be base64-decodable
        let id = AzureRequestBuilder.blockID(index: 42)
        #expect(Data(base64Encoded: id) != nil)
    }
}
