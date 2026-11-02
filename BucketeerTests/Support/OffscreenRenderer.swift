//
//  OffscreenRenderer.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import AppKit
import SwiftUI
import Vision
import XCTest

/// Renders a SwiftUI view into an off-screen window that is never
/// ordered front (no focus, nothing on screen), writes a PNG for a
/// visual check and returns the text recognised in the rendered pixels
/// (Vision OCR), so tests can assert that key content was drawn.
/// Accessibility is not used: SwiftUI builds no accessibility tree for
/// a window that is never shown.
@MainActor
enum OffscreenRenderer {
    static let outputDirectory = URL(fileURLWithPath: NSHomeDirectory())
        .appending(path: "tmp-karolina/bucketeer/viewrender", directoryHint: .isDirectory)

    struct Result {
        let texts: [String]
        let png: Data

        /// OCR misreads small UI text ("l" for "I", Cyrillic "К" for
        /// "K", a dropped letter), so a fragment counts as present when
        /// some window of a recognised line is at least 80 % similar.
        func contains(_ fragment: String) -> Bool {
            let needle = Self.normalised(fragment)
            return texts.contains { line in
                Self.bestSimilarity(of: needle, in: Self.normalised(line)) >= 0.8
            }
        }

        private static func normalised(_ text: String) -> [Character] {
            let confusables: [Character: Character] = ["к": "k", "і": "i", "о": "o", "а": "a", "е": "e", "с": "c",
                                                       "l": "i", "1": "i", "|": "i", "0": "o"]
            return text.lowercased().map { confusables[$0] ?? $0 }
        }

        private static func bestSimilarity(of needle: [Character], in haystack: [Character]) -> Double {
            guard !needle.isEmpty else { return 1 }
            guard haystack.count >= needle.count else {
                return 1 - Double(editDistance(needle, haystack)) / Double(needle.count)
            }
            var best = 0.0
            for start in 0...(haystack.count - needle.count) {
                let window = Array(haystack[start..<(start + needle.count)])
                best = max(best, 1 - Double(editDistance(needle, window)) / Double(needle.count))
                if best == 1 { break }
            }
            return best
        }

        private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
            var previous = Array(0...b.count)
            for (i, ca) in a.enumerated() {
                var current = [i + 1]
                for (j, cb) in b.enumerated() {
                    current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (ca == cb ? 0 : 1)))
                }
                previous = current
            }
            return previous[b.count]
        }
    }

    static func render<Content: View>(
        _ view: Content,
        name: String,
        size: CGSize = CGSize(width: 900, height: 600),
        settle: Duration = .milliseconds(400),
        expected: [String] = [],
        waitLimit: Duration = .seconds(5),
        afterAppear: (@MainActor () async -> Void)? = nil
    ) async throws -> Result {
        TestLocalization.install()
        // Views read `NSApp` (e.g. the app icon); create the shared
        // application object without activating or running it.
        _ = NSApplication.shared
        // Opaque like a real window; dark text on transparent pixels
        // would be invisible to OCR and in the PNG.
        let root = view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.contentView = host
        // Let `.task` / `.onAppear` work and SwiftUI layout settle.
        try await Task.sleep(for: settle)
        // State staged after the view's own initial load (which would
        // otherwise overwrite it), e.g. an error from a later reload.
        if let afterAppear {
            await afterAppear()
            try await Task.sleep(for: settle)
        }
        // Async loads finish at their own pace: recapture until every
        // expected fragment is drawn or the deadline passes.
        let deadline = ContinuousClock.now + waitLimit
        var capture = try snapshot(host, size: size)
        while !expected.allSatisfy(capture.contains), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(250))
            capture = try snapshot(host, size: size)
        }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try capture.png.write(to: outputDirectory.appending(path: "\(name).png"))
        window.contentView = nil
        window.close()
        return capture
    }

    private static func snapshot(_ host: NSView, size: CGSize) throws -> Result {
        host.layoutSubtreeIfNeeded()
        // 2x like a Retina display: sharper PNGs, and OCR reads small
        // footnote text reliably.
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        return Result(texts: try recognizedText(in: bitmap), png: png)
    }

    private static func recognizedText(in bitmap: NSBitmapImageRep) throws -> [String] {
        let image = try XCTUnwrap(bitmap.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}
