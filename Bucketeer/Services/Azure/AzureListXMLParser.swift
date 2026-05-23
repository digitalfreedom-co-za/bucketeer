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

    struct Container: Sendable {
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

    struct BlobListing: Sendable {
        let blobs: [Blob]
        let prefixes: [String]
        /// `NextMarker` is non-empty when the response was truncated.
        let nextMarker: String?
    }

    struct Blob: Sendable {
        let name: String
        let size: Int64
        let lastModified: Date?
        let etag: String?
        let contentType: String?
        let accessTier: String?
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
        case "Blob":
            guard !name.isEmpty else { return }
            blobs.append(
                .init(
                    name: name,
                    size: size,
                    lastModified: lastModified,
                    etag: etag,
                    contentType: contentType,
                    accessTier: accessTier
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
