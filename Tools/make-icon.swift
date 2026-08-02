#!/usr/bin/env swift
//
// Generates AppIcon.iconset. Run by build.sh, which then calls iconutil.
//
// Claude's own icon is a clay squircle holding a white burst, so this is
// deliberately the inverse — a white tile holding a clay burst. Same visual
// family, not mistakable for the real app in Finder or Spotlight.
//
// The spoke table is the same one measured in StatusIcon.swift; it is repeated
// here because a standalone script cannot import the app target.

import AppKit
import Foundation

let spokes: [(angle: Double, reach: Double)] = [
    (7.8, 0.90), (46.8, 0.91), (81.3, 0.91), (117.8, 1.02),
    (148.3, 0.98), (182.0, 0.95), (214.4, 0.92), (238.8, 0.97),
    (267.5, 0.95), (298.0, 0.94), (316.6, 0.96), (345.1, 0.92),
]

let tile = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let hairline = NSColor(srgbRed: 0xE7 / 255.0, green: 0xE7 / 255.0, blue: 0xE7 / 255.0, alpha: 1)
let clay = NSColor(srgbRed: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0, alpha: 1)

/// Apple's icon corners are a superellipse, not a circular round-rect. A plain
/// rounded rectangle reads visibly bulgier next to real app icons.
func squircle(in rect: CGRect, exponent: Double = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / exponent)
        let y = b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / exponent)
        let point = CGPoint(x: cx + x, y: cy + y)
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

func render(size: Int) -> Data {
    let side = CGFloat(size)
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    let context = CGContext(data: &pixels, width: size, height: size,
                            bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    // macOS leaves roughly a 10% margin around the tile itself.
    let inset = side * 0.098
    let tileRect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let body = squircle(in: tileRect)

    context.addPath(body)
    context.setFillColor(tile.cgColor)
    context.fillPath()

    if side >= 64 {
        context.addPath(body)
        context.setStrokeColor(hairline.cgColor)
        context.setLineWidth(max(1, side / 256))
        context.strokePath()
    }

    let center = CGPoint(x: tileRect.midX, y: tileRect.midY)
    let outer = tileRect.width / 2 * 0.66
    let inner = outer * 0.41
    let thickness = tileRect.width / 2 * (4.5 / 36.0)

    context.setStrokeColor(clay.cgColor)
    context.setFillColor(clay.cgColor)
    context.setLineWidth(thickness)
    context.setLineCap(.round)
    for spoke in spokes {
        let radians = spoke.angle * .pi / 180
        let dx = cos(radians), dy = sin(radians)
        context.move(to: CGPoint(x: center.x + dx * inner, y: center.y + dy * inner))
        context.addLine(to: CGPoint(x: center.x + dx * outer * spoke.reach,
                                    y: center.y + dy * outer * spoke.reach))
        context.strokePath()
    }
    context.fillEllipse(in: CGRect(x: center.x - inner, y: center.y - inner,
                                   width: inner * 2, height: inner * 2))

    let image = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: side, height: side)
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <out.iconset>\n".utf8))
    exit(1)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// The set iconutil expects.
let variants: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for variant in variants {
    try render(size: variant.size).write(to: out.appendingPathComponent(variant.name))
}
print("wrote \(variants.count) images to \(out.path)")
