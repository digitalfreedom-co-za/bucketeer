//
//  AzureListXMLParser.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation

/// Wraps Apple's event-driven `XMLParser` for the two Azure list
/// responses we need: container listing and hierarchical blob listing.
/// Both responses are small (≤ a few thousand entries per page) so a
/// fully buffered parse is fine.
enum AzureListXMLParser {

    // MARK: - Containers

    public struct Container: Sendable {
        let name: String
        let lastModified: Date?
    }

    static func parseContainers(_ data: Data) throws -> [Container] {
        let delegate = ContainerDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw BucketeerError.providerError(
                statusCode: 0,
                message: parser.parserError?.localizedDescription
                    ?? "Failed to parse Azure container list."
            )
        }
        return delegate.containers
    }

    // MARK: - Blobs

    public struct BlobListing: Sendable {
        let blobs: [Blob]
        let prefixes: [String]
        /// `NextMarker` is non-empty when the response was truncated.
        let nextMarker: String?
    }

    public struct Blob: Sendable {
        let name: String
        let size: Int64
        let lastModified: Date?
        let etag: String?
        let contentType: String?
        let accessTier: String?
        /// `<Snapshot>` timestamp when the request asked for
        /// `include=snapshots`. `nil` for the live blob. Phase 13.6
        /// Azure parity.
        let snapshot: String?
    }

    static func parseBlobs(_ data: Data) throws -> BlobListing {
        let delegate = BlobDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw BucketeerError.providerError(
                statusCode: 0,
                message: parser.parserError?.localizedDescription
                    ?? "Failed to parse Azure blob list."
            )
        }
        return BlobListing(
            blobs: delegate.blobs,
            prefixes: delegate.prefixes,
            nextMarker: delegate.nextMarker?.isEmpty == true ? nil : delegate.nextMarker
        )
    }

    // MARK: - Date

    /// Azure timestamps are RFC 1123 (`Sun, 24 May 2026 12:34:56 GMT`).
    /// Centralised so the parsers don't both construct their own.
    static func parseDate(_ string: String) -> Date? {
        sharedFormatter.date(from: string)
    }
    private static let sharedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return f
    }()

    // MARK: - Error responses

    /// Parse Azure's tag envelope:
    /// `<?xml ...?><Tags><TagSet><Tag><Key>k</Key><Value>v</Value></Tag>…</TagSet></Tags>`.
    /// Returns `[:]` when the envelope is empty or malformed — the
    /// caller renders that as "no tags set". Phase 13.7 Azure parity.
    static func parseTags(_ data: Data) -> [String: String] {
        guard !data.isEmpty else { return [:] }
        let delegate = TagDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return [:] }
        return delegate.tags
    }

    /// Best-effort parse of Azure's error envelope:
    /// `<?xml ...?><Error><Code>...</Code><Message>...</Message></Error>`.
    /// Returns `(code, message)` or `nil` if the body is not a recognised
    /// error envelope. Falls back to `x-ms-error-code` header lookup at
    /// the caller layer.
    static func parseError(_ data: Data) -> (code: String?, message: String?)? {
        guard !data.isEmpty else { return nil }
        let delegate = ErrorDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.sawErrorRoot else { return nil }
        return (delegate.code, delegate.message)
    }
}

// MARK: - Container delegate

private final class ContainerDelegate: NSObject, XMLParserDelegate {
    var containers: [AzureListXMLParser.Container] = []

    private var currentElement: String = ""
    private var currentName: String = ""
    private var currentLastModified: Date?

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "Container" {
            currentName = ""
            currentLastModified = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch currentElement {
        case "Name":
            currentName += string
        case "Last-Modified":
            // Concatenate first, parse on element close — characters
            // can arrive in chunks.
            pendingLastModified += string
        default:
            break
        }
    }

    private var pendingLastModified: String = ""

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "Last-Modified":
            currentLastModified = AzureListXMLParser.parseDate(
                pendingLastModified.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            pendingLastModified = ""
        case "Container":
            let name = currentName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                containers.append(
                    .init(name: name, lastModified: currentLastModified)
                )
            }
        default:
            break
        }
        currentElement = ""
    }
}

// MARK: - Blob delegate

private final class BlobDelegate: NSObject, XMLParserDelegate {
    var blobs: [AzureListXMLParser.Blob] = []
    var prefixes: [String] = []
    var nextMarker: String?

    private var path: [String] = []
    private var name: String = ""
    private var size: Int64 = 0
    private var lastModified: Date?
    private var etag: String?
    private var contentType: String?
    private var accessTier: String?
    private var snapshot: String?

    private var buffer: String = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        path.append(elementName)
        buffer = ""
        if elementName == "Blob" {
            name = ""
            size = 0
            lastModified = nil
            etag = nil
            contentType = nil
            accessTier = nil
            snapshot = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        defer {
            buffer = ""
            if !path.isEmpty { path.removeLast() }
        }
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = path.count >= 2 ? path[path.count - 2] : ""

        // Top-level NextMarker — only emit when actually inside an
        // EnumerationResults child, never inside a nested element.
        if elementName == "NextMarker" {
            nextMarker = trimmed
            return
        }

        // BlobPrefix → "common prefix" pseudo-folder
        if elementName == "Name" && parent == "BlobPrefix" {
            if !trimmed.isEmpty {
                prefixes.append(trimmed)
            }
            return
        }

        // Blob/* properties
        switch elementName {
        case "Name" where parent == "Blob":
            name = trimmed
        case "Content-Length":
            size = Int64(trimmed) ?? 0
        case "Last-Modified":
            lastModified = AzureListXMLParser.parseDate(trimmed)
        case "Etag":
            etag = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        case "Content-Type":
            contentType = trimmed.isEmpty ? nil : trimmed
        case "AccessTier":
            accessTier = trimmed.isEmpty ? nil : trimmed
        case "Snapshot" where parent == "Blob":
            snapshot = trimmed.isEmpty ? nil : trimmed
        case "Blob":
            guard !name.isEmpty else { return }
            blobs.append(
                .init(
                    name: name,
                    size: size,
                    lastModified: lastModified,
                    etag: etag,
                    contentType: contentType,
                    accessTier: accessTier,
                    snapshot: snapshot
                )
            )
        default:
            break
        }
    }
}

// MARK: - Error delegate

private final class ErrorDelegate: NSObject, XMLParserDelegate {
    var sawErrorRoot = false
    var code: String?
    var message: String?

    private var current: String = ""
    private var buffer: String = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "Error" { sawErrorRoot = true }
        current = elementName
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "Code":     code = trimmed
        case "Message":  message = trimmed
        default:         break
        }
        current = ""
        buffer = ""
    }
}

// MARK: - Tag delegate (Phase 13.7 Azure parity)

private final class TagDelegate: NSObject, XMLParserDelegate {
    var tags: [String: String] = [:]
    private var path: [String] = []
    private var buffer: String = ""
    private var currentKey: String = ""
    private var currentValue: String = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        path.append(elementName)
        buffer = ""
        if elementName == "Tag" {
            currentKey = ""
            currentValue = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        defer {
            buffer = ""
            if !path.isEmpty { path.removeLast() }
        }
        // Codex R4 (low): only trim the key (Azure tag keys are
        // alphanumeric + a few punct chars, never whitespace).
        // Leave the value verbatim — leading / trailing spaces in a
        // tag value are legitimate user data and trimming them
        // would corrupt the round-trip when saveMetadata writes
        // the value back.
        switch elementName {
        case "Key":
            currentKey = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        case "Value":
            currentValue = buffer
        case "Tag":
            guard !currentKey.isEmpty else { return }
            tags[currentKey] = currentValue
        default:
            break
        }
    }
}
