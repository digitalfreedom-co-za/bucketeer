//
//  UploadFileIntent.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import AppIntents
import UniformTypeIdentifiers
import BucketeerCore

/// "Upload a file to a Bucketeer bucket." Phase 13.12. Queues the
/// upload through the existing `TransferManager` and returns the
/// transfer ID for Shortcuts that want to react on completion.
struct UploadFileIntent: AppIntent {
    static let title: LocalizedStringResource = "Upload file to bucket"
    static let description = IntentDescription(
        "Queues a local file for upload to the chosen bucket. The upload runs in the background."
    )

    @Parameter(
        title: "File",
        supportedTypeIdentifiers: ["public.item"]
    )
    var file: IntentFile

    @Parameter(title: "Account")
    var account: AccountEntity

    @Parameter(title: "Bucket")
    var bucket: String

    @Parameter(title: "Key", description: "Destination key inside the bucket, including any folder prefix.")
    var key: String

    static var parameterSummary: some ParameterSummary {
        Summary("Upload \(\.$file) as \(\.$key) in \(\.$bucket) on \(\.$account)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let container = try await AppIntentsBridge.shared.container()
        let live = try await AppIntentsBridge.shared.liveAccount(for: account)

        // IntentFile exposes the URL only when the file is bookmarked
        // / referenced from disk; for in-memory data we materialise a
        // temp file so the existing TransferManager can mmap it.
        let localURL: URL
        if let fileURL = file.fileURL {
            localURL = fileURL
        } else {
            let ext = file.type?.preferredFilenameExtension
                ?? { let e = URL(fileURLWithPath: file.filename).pathExtension; return e.isEmpty ? "bin" : e }()
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try file.data.write(to: temp)
            localURL = temp
        }

        let contentType = UTType(filenameExtension: localURL.pathExtension)?.preferredMIMEType
        let id = await container.transferManager.enqueueUpload(
            account: live,
            bucket: bucket,
            key: key,
            localURL: localURL,
            contentType: contentType
        )
        return .result(value: id.uuidString)
    }
}
