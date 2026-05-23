//
//  S3ObjectRef.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import UniformTypeIdentifiers
import CoreTransferable

/// Drag payload for intra-app drag-and-drop. Carries enough identity to
/// dispatch a server-side copy (same account) or a cross-account
/// download+upload round-trip without re-fetching object metadata.
///
/// Uses a custom UTI registered as `importedAs` so the type is
/// recognised without needing an `UTExportedTypeDeclarations` entry in
/// `Info.plist` — perfectly fine for in-process drags. The future File
/// Provider extension target will declare the same UTI as an
/// `importedAs` so it can read drag payloads originating in the host app.
struct S3ObjectRef: Codable, Hashable, Sendable {
    let accountID: UUID
    let bucket: String
    let key: String
    let displayName: String
    let size: Int64
    let etag: String
    let isFolder: Bool
}

extension S3ObjectRef: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .bucketeerObjectRef)
    }
}

extension UTType {
    /// Custom in-process UTI for intra-app object drags. Both the host
    /// app and (later) the File Provider extension import the same
    /// identifier so payloads round-trip without an exported declaration.
    static let bucketeerObjectRef = UTType(
        importedAs: "za.co.digitalfreedom.bucketeer.object-ref"
    )
}
