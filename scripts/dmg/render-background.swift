#!/usr/bin/env swift
// Renders the DMG installer background at 1x and 2x.
//
//   swift scripts/dmg/render-background.swift <output directory>
//
// A black installer in the app icon's identity: the original CTL wordmark and
// the product name at the top, the app and Applications with an accent arrow,
// and an instruction. Layout (points, top-left origin) must match
// scripts/package-dmg.sh:
// window content 660 × 420; app icon centered at (180, 220); Applications
// shortcut centered at (480, 220); icon size 128.

import AppKit

let width: CGFloat = 660
let height: CGFloat = 420
let appCenter = CGPoint(x: 180, y: 220)
let applicationsCenter = CGPoint(x: 480, y: 220)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawText(_ string: String, in ctx: CGContext, font: NSFont, color: NSColor, centerX: CGFloat, baselineY: CGFloat, kern: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    let bounds = CTLineGetBoundsWithOptions(line, [])
    ctx.saveGState()
    ctx.translateBy(x: centerX - bounds.width / 2, y: baselineY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

/// The original "CTL" wordmark (white on clear), written by generate-app-icon.swift.
let wordmark: CGImage? = {
    let script = URL(filePath: CommandLine.arguments.first!)
    let root = script.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appending(path: "calender_time_logger/calender_time_logger/Resources/Assets.xcassets/CTLWordmark.imageset/ctl_wordmark.png")
    return NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
}()

/// A light, rounded plate behind a Finder label. Finder draws file names in dark
/// text over a custom background whatever the system appearance, so on the dark
/// installer each label gets its own plate. Centers and widths are measured from
/// Finder's label layout at text size 13 (see scripts/package-dmg.sh).
func drawLabelPlate(in ctx: CGContext, centerX: CGFloat, width: CGFloat) {
    let rect = CGRect(x: centerX - width / 2, y: 290, width: width, height: 28)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.setFillColor(rgb(0xECEBF1))
    ctx.fillPath()
}

func render(scale: CGFloat) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8,
                        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.translateBy(x: 0, y: height * scale)
    ctx.scaleBy(x: scale, y: -scale)

    // Black, like the app icon, lifting very slightly toward the bottom.
    let ground = CGGradient(colorsSpace: space, colors: [rgb(0x000000), rgb(0x141319)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(ground, start: .zero, end: CGPoint(x: 0, y: height), options: [])

    // The original CTL wordmark, centered, then the product name.
    if let wordmark {
        let markWidth: CGFloat = 104
        let markHeight = markWidth * CGFloat(wordmark.height) / CGFloat(wordmark.width)
        let rect = CGRect(x: width / 2 - markWidth / 2, y: 34, width: markWidth, height: markHeight)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: rect.midY * 2)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(wordmark, in: rect)
        ctx.restoreGState()
    }
    drawText("Calendar Time Logger", in: ctx, font: .systemFont(ofSize: 17, weight: .semibold),
             color: NSColor(white: 1, alpha: 0.92), centerX: width / 2, baselineY: 108)

    // Arrow from the app to Applications: a thin accent line with a chevron head.
    let startX = appCenter.x + 88, endX = applicationsCenter.x - 88, y = appCenter.y
    ctx.saveGState()
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: startX, y: y))
    arrow.addLine(to: CGPoint(x: endX, y: y))
    arrow.move(to: CGPoint(x: endX - 11, y: y - 10))
    arrow.addLine(to: CGPoint(x: endX, y: y))
    arrow.addLine(to: CGPoint(x: endX - 11, y: y + 10))
    ctx.addPath(arrow)
    ctx.setLineWidth(3)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let accent = CGGradient(colorsSpace: space, colors: [rgb(0x9B55EE), rgb(0x4A7BF7)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(accent, start: CGPoint(x: startX, y: 0), end: CGPoint(x: endX, y: 0), options: [])
    ctx.restoreGState()

    // Plates for Finder's dark label text.
    drawLabelPlate(in: ctx, centerX: appCenter.x, width: 184)
    drawLabelPlate(in: ctx, centerX: applicationsCenter.x, width: 98)

    // Instruction.
    drawText("Drag Calendar Time Logger to Applications to install", in: ctx,
             font: .systemFont(ofSize: 13, weight: .medium), color: NSColor(white: 1, alpha: 0.62),
             centerX: width / 2, baselineY: 378)

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: width, height: height)
    return rep.representation(using: .png, properties: [:])!
}

let output = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try render(scale: 1).write(to: output.appending(path: "background.png"))
try render(scale: 2).write(to: output.appending(path: "background@2x.png"))
print("Rendered DMG background (660 × 420 pt, 1x and 2x) to \(output.path(percentEncoded: false))")
