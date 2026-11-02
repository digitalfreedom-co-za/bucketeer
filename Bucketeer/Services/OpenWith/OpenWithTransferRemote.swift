//
//  OpenWithTransferRemote.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation
import UniformTypeIdentifiers
import BucketeerCore

/// Backs the round-trip with the real services: HEAD through the
/// provider router, uploads through the transfer queue so client-side
/// encryption, bandwidth limit and activity log all apply.
struct OpenWithTransferRemote: OpenWithRemote {
    let browser: any S3Browsing
    let transferManager: TransferManager
    let accountStore: any AccountStoring

    func currentETag(of object: RemoteObjectRef) async throws -> String? {
        let account = try await account(for: object)
        do {
            let head = try await browser.head(account: account, bucket: object.bucket, key: object.key)
            return head.etag.isEmpty ? nil : head.etag
        } catch BucketeerError.objectNotFound {
            return nil
        }
    }

    func upload(_ localURL: URL, to object: RemoteObjectRef, ifMatch: String?) async throws -> ConditionalUploadResult {
        let account = try await account(for: object)
        let contentType = UTType(filenameExtension: localURL.pathExtension)?.preferredMIMEType
        if let ifMatch {
            switch await transferManager.uploadIfUnchanged(
                account: account,
                bucket: object.bucket,
                key: object.key,
                localURL: localURL,
                contentType: contentType,
                ifMatch: ifMatch
            ) {
            case .uploaded: return .uploaded
            case .preconditionFailed: return .preconditionFailed
            case .failed(let message): throw BucketeerError.unknown(message: message)
            case .cancelled: throw BucketeerError.cancelled
            }
        }
        let id = await transferManager.enqueueUpload(
            account: account,
            bucket: object.bucket,
            key: object.key,
            localURL: localURL,
            contentType: contentType
        )
        switch await transferManager.awaitCompletion(id: id) {
        case .completed: return .uploaded
        case .failed(let message): throw BucketeerError.unknown(message: message)
        default: throw BucketeerError.cancelled
        }
    }

    private func account(for object: RemoteObjectRef) async throws -> S3Account {
        guard let account = try await accountStore.all().first(where: { $0.id == object.accountID }) else {
            throw BucketeerError.unknown(message: String(
                localized: "openWith.error.accountGone",
                defaultValue: "The account of this file no longer exists."
            ))
        }
        return account
    }
}
