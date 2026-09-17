#!/usr/bin/env swift
// Generates the Calendar Time Logger app icon and brand logo images.
//
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift scripts/generate-app-icon.swift
//
// The mark is flat: a solid black body and the white "CTL" wordmark, nothing
// else — no stroke, no baked shadow, no gradient. The wordmark is the original
// artwork: its glyphs are lifted from logo.png at the repository root (which is
// left unchanged) as an anti-aliased mask and only ever scaled down, so every
// size keeps the original letterforms. The smallest sizes give the wordmark a
// larger share of the tile so "CTL" stays legible.
//
// It also writes `CTLWordmark.imageset`, the same mask as a white-on-clear
// image, which the app draws in the menu bar mark and the welcome screen.
//
// Two shapes are produced, because macOS draws the two uses differently:
//
// - **Full bleed**, for `Resources/AppIcon.icns` (the app icon). macOS masks an
//   `.icns` app icon into the system squircle, so artwork that fills the canvas
//   fills the whole tile in Finder, the Dock, and Launchpad.
// - **Rounded**, an 824 px continuous-corner body inside a 1024 px canvas, for
//   the `BrandLogo` images the app draws itself (About, onboarding, the menu bar
//   popover footer) and for the DMG volume icon, which are not masked.
//
// The app icon is deliberately **not** an asset-catalog `AppIcon.appiconset`:
// on macOS 26 and later an asset-catalog app icon is composited onto a gray
// compatibility plate and is not masked, which draws a visible border around a
// dark icon. The `.icns` path has no plate. (Icon Composer's `.icon` format is
// the other supported route, but it cannot be authored from a script.) The
// appiconset PNGs are still generated, in the rounded shape, for the installer
// and the documentation.

import AppKit
import SwiftUI

let root = URL(filePath: CommandLine.arguments.first!).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appending(path: "calender_time_logger/calender_time_logger/Resources")
let assets = resources.appending(path: "Assets.xcassets")
let iconSet = assets.appending(path: "AppIcon.appiconset")
let brandSet = assets.appending(path: "BrandLogo.imageset")
let designDir = root.appending(path: "Documentation/Design/Assets")
let wordmarkSet = assets.appending(path: "CTLWordmark.imageset")

/// The white "CTL" from the original logo, cropped to its glyphs, as a
/// white image whose alpha is the artwork's luminance.
let wordmark: CGImage = {
    guard let source = NSImage(contentsOf: root.appending(path: "logo.png"))?
        .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("logo.png not found at the repository root"); exit(1)
    }
    let w = source.width, h = source.height
    let gray = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    gray.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
    let luminance = gray.data!.assumingMemoryBound(to: UInt8.self)
    // Glyph bounds (rows counted from the top of the bitmap).
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h { for x in 0..<w where luminance[y * w + x] > 24 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    let pad = 2
    minX = max(0, minX - pad); minY = max(0, minY - pad); maxX = min(w - 1, maxX + pad); maxY = min(h - 1, maxY + pad)
    let cw = maxX - minX + 1, ch = maxY - minY + 1
    let rgba = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw * 4,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let out = rgba.data!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<ch { for x in 0..<cw {
        let a = luminance[(y + minY) * w + (x + minX)]
        let i = (y * cw + x) * 4
        // Premultiplied white: every channel equals alpha. Bitmap memory is top row first.
        out[i] = a; out[i + 1] = a; out[i + 2] = a; out[i + 3] = a
    } }
    return rgba.makeImage()!
}()

/// sRGB color from hex.
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Continuous (squircle) rounded rectangle, as used by macOS icons.
func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
    RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath
}

enum Shape {
    /// Fills the canvas; macOS masks it into the system squircle.
    case fullBleed
    /// An 824 px body with 100 px margins, for images nothing masks.
    case rounded
}

func render(pixels: Int, shape: Shape) -> Data {
    let size = CGFloat(pixels)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    // Flip to top-left origin so the layout reads like the design grid.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    let small = pixels <= 32
    let unit = size / 1024
    let body: CGRect
    let path: CGPath
    switch shape {
    case .fullBleed:
        body = CGRect(x: 0, y: 0, width: size, height: size)
        path = CGPath(rect: body, transform: nil)
    case .rounded:
        body = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
        path = squircle(body, radius: 185 * unit)
    }

    ctx.saveGState()
    ctx.addPath(path)
    ctx.setFillColor(rgb(0x000000))
    ctx.fillPath()
    ctx.restoreGState()

    // The original "CTL" wordmark, centered. The full-bleed shape has no margin
    // of its own, so the wordmark's width leaves room for the masked corners.
    // In logo.png the glyphs span 84% of the square; the icon keeps them a
    // little smaller to sit inside the system squircle, and larger at 16 and
    // 32 px, where legibility matters more than margin.
    let share: CGFloat = small ? 0.82 : (shape == .fullBleed ? 0.70 : 0.72)
    let markWidth = body.width * share
    let markHeight = markWidth * CGFloat(wordmark.height) / CGFloat(wordmark.width)
    let markRect = CGRect(x: body.midX - markWidth / 2, y: body.midY - markHeight / 2, width: markWidth, height: markHeight)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    // Undo the top-left flip locally: CGImage draws bottom-up.
    ctx.translateBy(x: 0, y: markRect.midY * 2)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(wordmark, in: markRect)
    ctx.restoreGState()

    let image = ctx.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

func write(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
    print("wrote \(url.path(percentEncoded: false).replacingOccurrences(of: root.path(percentEncoded: false), with: ""))")
}

// The app icon: full-bleed artwork, built into an .icns by iconutil.
let staging = FileManager.default.temporaryDirectory.appending(path: "AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
for (pixels, name) in [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
                       (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"),
                       (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x")] {
    try render(pixels: pixels, shape: .fullBleed).write(to: staging.appending(path: "\(name).png"))
}
let icns = resources.appending(path: "AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", staging.path(percentEncoded: false), "-o", icns.path(percentEncoded: false)]
try iconutil.run()
iconutil.waitUntilExit()
try FileManager.default.removeItem(at: staging)
guard iconutil.terminationStatus == 0 else {
    print("iconutil failed with status \(iconutil.terminationStatus)")
    exit(1)
}
print("wrote calender_time_logger/calender_time_logger/Resources/AppIcon.icns")

// Rounded artwork: the installer's volume icon, the in-app logo, and the docs.
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    try write(render(pixels: pixels, shape: .rounded), to: iconSet.appending(path: "icon_\(pixels).png"))
}
try write(render(pixels: 512, shape: .rounded), to: brandSet.appending(path: "logo_512.png"))
try write(render(pixels: 1024, shape: .rounded), to: brandSet.appending(path: "logo_1024.png"))
try write(render(pixels: 1024, shape: .rounded), to: designDir.appending(path: "AppIcon-1024.png"))

// The wordmark alone, white on clear, for the menu bar mark and the welcome screen.
let wordmarkPNG = NSBitmapImageRep(cgImage: wordmark).representation(using: .png, properties: [:])!
try write(wordmarkPNG, to: wordmarkSet.appending(path: "ctl_wordmark.png"))
try write(Data("""
{
  "images" : [ { "filename" : "ctl_wordmark.png", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : false, "template-rendering-intent" : "original" }
}
""".utf8), to: wordmarkSet.appending(path: "Contents.json"))
