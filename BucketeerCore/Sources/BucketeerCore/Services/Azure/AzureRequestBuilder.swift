//
//  AzureRequestBuilder.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation

/// Constructs the URLs and request shapes used by `AzureBlobObjectStore`
/// and `AzureBlobTransporter`. Pure; no side effects. The signer is
/// applied as a separate step after the builder hands back the URLRequest.
struct AzureRequestBuilder: Sendable {

    /// Base endpoint URL for this account — either the default
    /// `https://{accountName}.blob.core.windows.net` or a sovereign-cloud
    /// override the user provided in the Add/Edit sheet.
    let baseURL: URL

    init(account: S3Account) {
        if let override = account.endpointOverride {
            self.baseURL = override
        } else {
            let name = account.accountID ?? "missing-account-name"
            self.baseURL = URL(
                string: "https://\(name).blob.core.windows.net"
            )!
        }
    }

    // MARK: - URLs

    /// `GET /?comp=list` — list all containers in the storage account.
    func listContainersURL() -> URL {
        url(path: "/", query: [("comp", "list")])
    }

    /// `GET /{container}?restype=container&comp=list&prefix=...&delimiter=/&marker=...`
    /// — list blobs inside one container with hierarchical pagination.
    func listBlobsURL(
        container: String,
        prefix: String,
        marker: String?
    ) -> URL {
        var query: [(String, String)] = [
            ("restype", "container"),
            ("comp", "list"),
            ("delimiter", "/")
        ]
        if !prefix.isEmpty {
            query.append(("prefix", prefix))
        }
        if let marker, !marker.isEmpty {
            query.append(("marker", marker))
        }
        return url(path: "/" + container, query: query)
    }

    /// `HEAD /{container}/{blob}` — properties (Get Blob Properties).
    func blobPropertiesURL(container: String, blob: String) -> URL {
        url(path: blobPath(container: container, blob: blob))
    }

    /// `GET /{container}/{blob}` — body download.
    func blobDownloadURL(container: String, blob: String) -> URL {
        url(path: blobPath(container: container, blob: blob))
    }

    /// `PUT /{container}/{blob}` — single-shot Block Blob upload or
    /// blob-target for server-side copy.
    func blobURL(container: String, blob: String) -> URL {
        url(path: blobPath(container: container, blob: blob))
    }

    /// `DELETE /{container}/{blob}`.
    func deleteBlobURL(container: String, blob: String) -> URL {
        url(path: blobPath(container: container, blob: blob))
    }

    /// `PUT /{container}/{blob}?comp=block&blockid=...` — one block stage
    /// during multipart upload.
    func putBlockURL(container: String, blob: String, blockID: String) -> URL {
        url(
            path: blobPath(container: container, blob: blob),
            query: [("comp", "block"), ("blockid", blockID)]
        )
    }

    /// `PUT /{container}/{blob}?comp=blocklist` — commit a multipart
    /// upload by sending the ordered block list.
    func putBlockListURL(container: String, blob: String) -> URL {
        url(
            path: blobPath(container: container, blob: blob),
            query: [("comp", "blocklist")]
        )
    }

    // MARK: - Source identifiers

    /// Fully-qualified URL for the source blob of a `Copy Blob` request.
    /// Goes into the `x-ms-copy-source` header.
    func absoluteBlobURL(container: String, blob: String) -> URL {
        url(path: blobPath(container: container, blob: blob))
    }

    // MARK: - Metadata + tags (Phase 13.7 — Azure parity)

    /// `PUT /{container}/{blob}?comp=metadata` — replaces every
    /// `x-ms-meta-*` header on the blob with the supplied set.
    func setBlobMetadataURL(container: String, blob: String) -> URL {
        url(
            path: blobPath(container: container, blob: blob),
            query: [("comp", "metadata")]
        )
    }

    /// `GET /{container}/{blob}?comp=tags` — list blob index tags.
    func getBlobTagsURL(container: String, blob: String) -> URL {
        url(
            path: blobPath(container: container, blob: blob),
            query: [("comp", "tags")]
        )
    }

    /// `PUT /{container}/{blob}?comp=tags` — replace the entire tag set.
    func setBlobTagsURL(container: String, blob: String) -> URL {
        url(
            path: blobPath(container: container, blob: blob),
            query: [("comp", "tags")]
        )
    }

    // MARK: - Versions / snapshots (Phase 13.6 — Azure parity)

    /// `GET /{container}?restype=container&comp=list&prefix=<blob>&include=snapshots`
    /// — Azure's equivalent of S3's listObjectVersions for one
    /// specific blob. Filtered post-hoc to the exact blob name.
    func listSnapshotsURL(container: String, blob: String) -> URL {
        url(
            path: "/" + container,
            query: [
                ("restype", "container"),
                ("comp", "list"),
                ("prefix", blob),
                ("include", "snapshots")
            ]
        )
    }

    /// `DELETE /{container}/{blob}?snapshot=<timestamp>` — delete one
    /// snapshot without touching the live blob.
    func deleteSnapshotURL(container: String, blob: String, snapshot: String) -> URL {
        url(
            path: blobPath(container: container, blob: blob),
            query: [("snapshot", snapshot)]
        )
    }

    /// Source URL for a Copy Blob operation that pulls from a
    /// specific snapshot. Goes into the `x-ms-copy-source` header.
    func snapshotSourceURL(container: String, blob: String, snapshot: String) -> URL {
        url(
            path: blobPath(container: container, blob: blob),
            query: [("snapshot", snapshot)]
        )
    }

    // MARK: - Bodies

    /// XML body for `Put Block List` — orders the previously-staged
    /// blocks. Latest-Wins is the default semantic.
    static func blockListXML(blockIDs: [String]) -> Data {
        var body = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<BlockList>"
        for id in blockIDs {
            body += "<Latest>\(id)</Latest>"
        }
        body += "</BlockList>"
        return Data(body.utf8)
    }

    /// Block IDs must all be the same base64 length within a single
    /// upload — pad the index with a fixed-width prefix so a 1-of-99
    /// upload signs identically to a 1-of-100 upload.
    static func blockID(index: Int) -> String {
        let raw = String(format: "block-%08d", index)
        return Data(raw.utf8).base64EncodedString()
    }

    /// XML body for `Set Blob Tags` — Azure's expected envelope.
    /// `<Tags><TagSet><Tag><Key>k</Key><Value>v</Value></Tag>…</TagSet></Tags>`
    static func tagsXML(tags: [String: String]) -> Data {
        var body = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<Tags><TagSet>"
        for (key, value) in tags.sorted(by: { $0.key < $1.key }) {
            body += "<Tag><Key>\(xmlEscape(key))</Key><Value>\(xmlEscape(value))</Value></Tag>"
        }
        body += "</TagSet></Tags>"
        return Data(body.utf8)
    }

    /// Minimal XML escape for the values that go into Set Blob Tags.
    /// Azure tag keys are alphanumeric + a small set, but values can
    /// contain spaces and a wider charset — escape the structural
    /// characters defensively.
    static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    // MARK: - Helpers

    private func blobPath(container: String, blob: String) -> String {
        let encodedBlob = Self.percentEncode(blob: blob)
        return "/\(container)/\(encodedBlob)"
    }

    private func url(path: String, query: [(String, String)] = []) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = path
        if !query.isEmpty {
            components.queryItems = query.map { name, value in
                URLQueryItem(name: name, value: value)
            }
        }
        return components.url!
    }

    /// Blob names are arbitrary UTF-8 with `/` as a structural separator.
    /// We percent-encode every reserved character except `/`, which we
    /// keep so virtual folders look right in the URL.
    static func percentEncode(blob: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        // `/` already allowed; everything else outside that set gets
        // encoded — covers space, `?`, `#`, `%`, etc.
        allowed.insert(charactersIn: "/")
        return blob.addingPercentEncoding(withAllowedCharacters: allowed) ?? blob
    }
}
