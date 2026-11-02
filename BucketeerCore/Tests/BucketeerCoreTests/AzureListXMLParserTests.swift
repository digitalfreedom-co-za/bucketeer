//
//  AzureListXMLParserTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import Testing
@testable import BucketeerCore

@Suite("AzureListXMLParser")
struct AzureListXMLParserTests {

    @Test("parseContainers extracts every <Container> name and last-modified date")
    func parsesContainerList() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <EnumerationResults>
          <Containers>
            <Container>
              <Name>photos</Name>
              <Properties>
                <Last-Modified>Sun, 24 May 2026 12:34:56 GMT</Last-Modified>
              </Properties>
            </Container>
            <Container>
              <Name>backups</Name>
              <Properties>
                <Last-Modified>Mon, 25 May 2026 09:00:00 GMT</Last-Modified>
              </Properties>
            </Container>
          </Containers>
        </EnumerationResults>
        """
        let containers = try AzureListXMLParser.parseContainers(Data(xml.utf8))
        #expect(containers.count == 2)
        #expect(containers[0].name == "photos")
        #expect(containers[1].name == "backups")
        #expect(containers[0].lastModified != nil)
    }

    @Test("parseBlobs extracts files + folder prefixes + next-marker")
    func parsesBlobListing() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <EnumerationResults>
          <Prefix>2026/</Prefix>
          <Delimiter>/</Delimiter>
          <Blobs>
            <BlobPrefix>
              <Name>2026/may/</Name>
            </BlobPrefix>
            <BlobPrefix>
              <Name>2026/june/</Name>
            </BlobPrefix>
            <Blob>
              <Name>2026/readme.txt</Name>
              <Properties>
                <Last-Modified>Sun, 24 May 2026 12:34:56 GMT</Last-Modified>
                <Etag>0x8DB12345</Etag>
                <Content-Length>4096</Content-Length>
                <Content-Type>text/plain</Content-Type>
                <AccessTier>Hot</AccessTier>
              </Properties>
            </Blob>
          </Blobs>
          <NextMarker>continuation-token-here</NextMarker>
        </EnumerationResults>
        """
        let listing = try AzureListXMLParser.parseBlobs(Data(xml.utf8))
        #expect(listing.prefixes == ["2026/may/", "2026/june/"])
        #expect(listing.blobs.count == 1)
        #expect(listing.blobs[0].name == "2026/readme.txt")
        #expect(listing.blobs[0].size == 4096)
        #expect(listing.blobs[0].etag == "0x8DB12345")
        #expect(listing.blobs[0].contentType == "text/plain")
        #expect(listing.blobs[0].accessTier == "Hot")
        #expect(listing.nextMarker == "continuation-token-here")
    }

    @Test("Empty NextMarker maps to nil — Azure emits it even when not truncated")
    func emptyNextMarker() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <EnumerationResults>
          <Blobs/>
          <NextMarker/>
        </EnumerationResults>
        """
        let listing = try AzureListXMLParser.parseBlobs(Data(xml.utf8))
        #expect(listing.nextMarker == nil)
    }

    @Test("parseError recognises the standard Azure error envelope")
    func parsesError() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <Error>
          <Code>BlobNotFound</Code>
          <Message>The specified blob does not exist.</Message>
        </Error>
        """
        let result = AzureListXMLParser.parseError(Data(xml.utf8))
        #expect(result?.code == "BlobNotFound")
        #expect(result?.message == "The specified blob does not exist.")
    }

    @Test("parseError returns nil for non-error XML")
    func parseErrorRejectsNonError() {
        let xml = "<?xml version=\"1.0\"?><Hello/>"
        #expect(AzureListXMLParser.parseError(Data(xml.utf8)) == nil)
    }

    @Test("parseError returns nil for empty body")
    func parseErrorEmpty() {
        #expect(AzureListXMLParser.parseError(Data()) == nil)
    }
}
