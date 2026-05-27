#!/usr/bin/env swift

// generate_app_icon.swift — draws the Bucketeer brand icon at
// exact pixel dimensions per slot using a raw CGContext, bypassing
// NSImage's automatic retina backing-store doubling that otherwise
// produces 2x-too-big PNGs.

import AppKit
import CoreGraphics
import CoreText

let brandTop    = CGColor(red: 0.13, green: 0.65, blue: 0.91, alpha: 1.0)
let brandBottom = CGColor(red: 0.04, green: 0.31, blue: 0.62, alpha: 1.0)
let white       = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let shadow      = CGColor(red: 0, green: 0, blue: 0, alpha: 0.18)

func render(side: Int) -> Data? {
    let size = CGFloat(side)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitsPerComponent = 8
    let bytesPerRow = side * 4
    guard let ctx = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Background squircle with gradient.
    let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
    let corner = size * 0.225
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [brandTop, brandBottom] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: []
    )
    ctx.restoreGState()

    // Bucket body.
    let bodyTopY:    CGFloat = size * 0.22
    let bodyBottomY: CGFloat = size * 0.66
    let bodyTopLeft     = CGPoint(x: size * 0.26, y: bodyTopY)
    let bodyTopRight    = CGPoint(x: size * 0.74, y: bodyTopY)
    let bodyBottomLeft  = CGPoint(x: size * 0.32, y: bodyBottomY)
    let bodyBottomRight = CGPoint(x: size * 0.68, y: bodyBottomY)

    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.012),
        blur: size * 0.025,
        color: shadow
    )
    let bodyPath = CGMutablePath()
    bodyPath.move(to: bodyTopLeft)
    bodyPath.addLine(to: bodyTopRight)
    bodyPath.addLine(to: bodyBottomRight)
    bodyPath.addLine(to: bodyBottomLeft)
    bodyPath.closeSubpath()
    ctx.addPath(bodyPath)
    ctx.setFillColor(white)
    ctx.fillPath()

    // Handle: 180° arc above the body.
    let handleY = bodyTopY
    let handleCenter = CGPoint(x: size * 0.50, y: handleY - size * 0.005)
    let handleRadius = (bodyTopRight.x - bodyTopLeft.x) * 0.5
    let handlePath = CGMutablePath()
    handlePath.addArc(
        center: handleCenter,
        radius: handleRadius,
        startAngle: 0,
        endAngle: .pi,
        clockwise: false
    )
    ctx.addPath(handlePath)
    ctx.setStrokeColor(white)
    ctx.setLineWidth(size * 0.045)
    ctx.setLineCap(.round)
    ctx.strokePath()

    // Upload chevrons inside the bucket.
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.setStrokeColor(brandBottom)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(size * 0.045)
    let chevronWidth = size * 0.20
    let chevronHeight = size * 0.10
    let chevronGap = size * 0.04
    let chevronCenterX = size * 0.50
    let lowerApexY = size * 0.30
    let upperApexY = lowerApexY + chevronHeight + chevronGap
    for apexY in [lowerApexY, upperApexY] {
        let chevron = CGMutablePath()
        chevron.move(to: CGPoint(x: chevronCenterX - chevronWidth / 2, y: apexY - chevronHeight))
        chevron.addLine(to: CGPoint(x: chevronCenterX, y: apexY))
        chevron.addLine(to: CGPoint(x: chevronCenterX + chevronWidth / 2, y: apexY - chevronHeight))
        ctx.addPath(chevron)
        ctx.strokePath()
    }

    guard let cgImage = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])
}

let fileManager = FileManager.default
let repoRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let iconsetURL = repoRoot
    .appendingPathComponent("Bucketeer")
    .appendingPathComponent("Assets.xcassets")
    .appendingPathComponent("AppIcon.appiconset")
let masterDir = repoRoot.appendingPathComponent("scripts/build")
try? fileManager.createDirectory(at: masterDir, withIntermediateDirectories: true)

let slots: [(name: String, side: Int)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024)
]

for slot in slots {
    guard let data = render(side: slot.side) else {
        print("Failed to render \(slot.name)")
        exit(1)
    }
    let url = iconsetURL.appendingPathComponent(slot.name)
    try data.write(to: url)
    print("Wrote \(slot.name) at \(slot.side)x\(slot.side)")
}

if let masterData = render(side: 1024) {
    let masterURL = masterDir.appendingPathComponent("bucketeer-icon-master-1024.png")
    try masterData.write(to: masterURL)
    print("Wrote master:", masterURL.path)
}

print("Done.")
