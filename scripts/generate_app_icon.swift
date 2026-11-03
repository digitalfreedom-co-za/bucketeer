#!/usr/bin/env swift

// generate_app_icon.swift — renders the Bucketeer app icon from the
// vector source scripts/icon/AppIcon-10e.svg into every slot listed in
// AppIcon.appiconset/Contents.json. Rendering is done by rsvg-convert
// (Homebrew: `brew install librsvg`), the same tool that produced the
// committed PNGs, so re-running reproduces them exactly.
//
// Run from the repository root:
//   swift scripts/generate_app_icon.swift [output-directory]
// The output directory defaults to Bucketeer/Assets.xcassets/AppIcon.appiconset.

import Foundation

struct IconSlot {
    let filename: String
    let pixels: Int
}

struct AppIconContents: Decodable {
    struct Image: Decodable {
        let filename: String?
        let size: String
        let scale: String
    }
    let images: [Image]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

/// Pixel edge length of a slot, e.g. size "16x16" at scale "2x" → 32.
func pixelSize(of image: AppIconContents.Image) -> Int? {
    guard let points = Double(image.size.split(separator: "x").first ?? ""),
          let scale = Double(image.scale.dropLast()) else { return nil }
    return Int(points * scale)
}

func loadSlots(from contentsURL: URL) -> [IconSlot] {
    guard let data = try? Data(contentsOf: contentsURL),
          let contents = try? JSONDecoder().decode(AppIconContents.self, from: data) else {
        fail("cannot read \(contentsURL.path)")
    }
    return contents.images.compactMap { image in
        guard let filename = image.filename else { return nil }
        guard let pixels = pixelSize(of: image) else {
            fail("cannot derive pixel size for \(filename)")
        }
        return IconSlot(filename: filename, pixels: pixels)
    }
}

func run(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    do {
        try process.run()
    } catch {
        fail("cannot launch \(arguments.first ?? ""): \(error.localizedDescription)")
    }
    process.waitUntilExit()
    return process.terminationStatus
}

func requireRsvgConvert() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = ["rsvg-convert"]
    process.standardOutput = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fail("rsvg-convert not found in PATH — install it with `brew install librsvg`")
    }
}

let fileManager = FileManager.default
let repoRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let iconsetURL = repoRoot.appendingPathComponent("Bucketeer/Assets.xcassets/AppIcon.appiconset")
let svgURL = repoRoot.appendingPathComponent("scripts/icon/AppIcon-10e.svg")
let outputURL = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], relativeTo: repoRoot)
    : iconsetURL

guard fileManager.fileExists(atPath: svgURL.path) else {
    fail("icon source not found at \(svgURL.path) — run from the repository root")
}
requireRsvgConvert()
do {
    try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
} catch {
    fail("cannot create \(outputURL.path): \(error.localizedDescription)")
}

for slot in loadSlots(from: iconsetURL.appendingPathComponent("Contents.json")) {
    let destination = outputURL.appendingPathComponent(slot.filename)
    let status = run([
        "rsvg-convert",
        "-w", String(slot.pixels),
        "-h", String(slot.pixels),
        "-o", destination.path,
        svgURL.path
    ])
    guard status == 0 else {
        fail("rsvg-convert failed for \(slot.filename) (exit \(status))")
    }
    print("Wrote \(slot.filename) at \(slot.pixels)x\(slot.pixels)")
}

print("Done.")
