//
//  S3ObjectTests.swift
//  BucketeerCoreTests
//

import Foundation
import Testing
@testable import BucketeerCore

@Suite("S3Object")
struct S3ObjectTests {

    @Test("knownLastModified hides the distantPast folder sentinel and keeps real dates")
    func knownLastModified() {
        let folder = S3Object(key: "photos/", size: 0, lastModified: .distantPast, etag: "", isFolder: true)
        #expect(folder.knownLastModified == nil)

        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let file = S3Object(key: "photos/a.jpg", size: 1, lastModified: date, etag: "x")
        #expect(file.knownLastModified == date)
    }
}
