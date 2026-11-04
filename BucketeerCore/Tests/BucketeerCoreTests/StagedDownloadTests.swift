//
//  StagedDownloadTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation
import Testing
@testable import BucketeerCore

@Suite("StagedDownload")
struct StagedDownloadTests {

    @Test("A download cancelled after its bytes arrived keeps the existing file")
    func cancelBeforePublishKeepsExistingFile() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("StagedDownloadTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("report.txt")
        try Data("existing".utf8).write(to: destination)

        let download = Task {
            try await StagedDownload.write(to: destination) { staging in
                try Data("new".utf8).write(to: staging)
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }

        await #expect(throws: CancellationError.self) { try await download.value }
        #expect(try Data(contentsOf: destination) == Data("existing".utf8))
    }
}
