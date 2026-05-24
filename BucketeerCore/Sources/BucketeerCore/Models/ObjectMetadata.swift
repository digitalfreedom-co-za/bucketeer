//
//  ObjectMetadata.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation

/// Bundle of user-editable bits of an object: HTTP-style metadata
/// (content type, cache control, content disposition, content
/// encoding, custom `x-amz-meta-*` keys) and object tags. Phase 13.7.
///
/// The struct is a "value object" — it represents one snapshot of the
/// editable bits at load time. Saving an edited copy is a single
/// `S3Browsing.saveMetadata` call that the service translates into
/// the right pair of provider RPCs.
public struct ObjectMetadata: Hashable, Sendable {
    /// HTTP `Content-Type`. Empty string represents "use the
    /// provider's default" — the editor turns the empty value into
    /// `nil` before persistence.
    public var contentType: String
    /// HTTP `Cache-Control`, e.g. `max-age=3600`.
    public var cacheControl: String
    /// HTTP `Content-Disposition`, e.g.
    /// `attachment; filename="report.pdf"`.
    public var contentDisposition: String
    /// HTTP `Content-Encoding`, e.g. `gzip`.
    public var contentEncoding: String
    /// `x-amz-meta-*` key/value pairs (S3) or `x-ms-meta-*` (Azure).
    /// Keys must be ASCII; the editor enforces lowercase + dash-
    /// separated tokens before persistence.
    public var userMetadata: [String: String]
    /// Object tags (S3 PutObjectTagging / Azure Set Blob Tags). Hard-
    /// capped at 10 entries by S3 / 10 by Azure — the UI enforces
    /// this before submit.
    public var tags: [String: String]
    /// Storage class string (e.g. STANDARD, INTELLIGENT_TIERING).
    /// Read-only in this editor; changing the class needs a
    /// CopyObject with `storageClass: …` which the dedicated phase
    /// 13.9 lifecycle editor handles.
    public let storageClass: String?

    public init(
        contentType: String = "",
        cacheControl: String = "",
        contentDisposition: String = "",
        contentEncoding: String = "",
        userMetadata: [String: String] = [:],
        tags: [String: String] = [:],
        storageClass: String? = nil
    ) {
        self.contentType = contentType
        self.cacheControl = cacheControl
        self.contentDisposition = contentDisposition
        self.contentEncoding = contentEncoding
        self.userMetadata = userMetadata
        self.tags = tags
        self.storageClass = storageClass
    }
}
