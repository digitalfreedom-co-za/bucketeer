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
