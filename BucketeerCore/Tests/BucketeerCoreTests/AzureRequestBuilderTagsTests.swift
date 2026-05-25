//
//  AzureRequestBuilderTagsTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import Foundation
import Testing
@testable import BucketeerCore

/// Phase 14 / Codex R3 coverage for the new Azure-parity helpers
/// in `AzureRequestBuilder`: XML escaping, control-scalar stripping,
/// HTTP-token validation, and header-value sanitisation.
@Suite("AzureRequestBuilder helpers")
struct AzureRequestBuilderTagsTests {

    @Test("xmlEscape replaces the five XML structural characters")
    func xmlEscapeStructural() {
        let raw = "a & b < c > d \" e ' f"
        let escaped = AzureRequestBuilder.xmlEscape(raw)
        #expect(escaped == "a &amp; b &lt; c &gt; d &quot; e &apos; f")
    }

    @Test("xmlEscape strips XML 1.0 illegal control scalars (Codex R3 low)")
    func xmlEscapeStripsControlChars() {
        // \u{0001} and \u{0008} are forbidden in XML 1.0. \u{0009}
        // (tab), \u{000A} (LF), \u{000D} (CR) are allowed.
        let raw = "ok\u{0001}-text\u{0008}-tab\u{0009}-keep"
        let escaped = AzureRequestBuilder.xmlEscape(raw)
        #expect(escaped == "ok-text-tab\u{0009}-keep")
    }

    @Test("sanitiseHeaderValue strips CR/LF/NUL but keeps tab")
    func sanitiseStripsCRLF() {
        let raw = "value\r\nInjected: yes\u{0000}done\tend"
        let sanitised = AzureRequestBuilder.sanitiseHeaderValue(raw)
        #expect(sanitised == "valueInjected: yesdone\tend")
    }

    @Test("isValidHeaderToken accepts RFC 9110 token characters")
    func tokenAccepts() {
        for name in ["a", "abc-123", "x-ms-meta-Foo", "X_Bar.42"] {
            #expect(AzureRequestBuilder.isValidHeaderToken(name),
                    "should accept '\(name)'")
        }
    }

    @Test("isValidHeaderToken rejects spaces, CR/LF, and structural punct")
    func tokenRejects() {
        for name in ["", "with space", "has\nnewline", "has\r", "comma,", "colon:", "quote\""] {
            #expect(!AzureRequestBuilder.isValidHeaderToken(name),
                    "should reject '\(name.debugDescription)'")
        }
    }

    @Test("tagsXML emits keys in sorted order for deterministic signatures")
    func tagsXMLIsSorted() {
        let xml = AzureRequestBuilder.tagsXML(tags: ["b": "2", "a": "1", "c": "3"])
        let text = String(decoding: xml, as: UTF8.self)
        // Keys should appear alphabetically.
        let posA = text.range(of: "<Key>a</Key>")!.lowerBound
        let posB = text.range(of: "<Key>b</Key>")!.lowerBound
        let posC = text.range(of: "<Key>c</Key>")!.lowerBound
        #expect(posA < posB && posB < posC)
    }

    @Test("tagsXML escapes hostile keys + values without breaking the envelope")
    func tagsXMLEscapes() {
        let xml = AzureRequestBuilder.tagsXML(tags: ["k&y": "<v>"])
        let text = String(decoding: xml, as: UTF8.self)
        #expect(text.contains("<Key>k&amp;y</Key>"))
        #expect(text.contains("<Value>&lt;v&gt;</Value>"))
    }
}
