#!/usr/bin/env swift

import AppKit
import Foundation

let output = CommandLine.arguments.dropFirst().first.map(URL.init(fileURLWithPath:))
    ?? URL(fileURLWithPath: "Support/AppIcon.icns")
let fileManager = FileManager.default
let iconset = output.deletingPathExtension().appendingPathExtension("iconset")
try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func drawIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let radius = CGFloat(size) * 0.22
    let rounded = NSBezierPath(roundedRect: rect.insetBy(dx: CGFloat(size) * 0.06, dy: CGFloat(size) * 0.06), xRadius: radius, yRadius: radius)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.26, blue: 0.54, alpha: 1),
        NSColor(calibratedRed: 0.20, green: 0.58, blue: 0.86, alpha: 1),
    ])?.draw(in: rounded, angle: 45)

    NSColor.white.withAlphaComponent(0.92).setStroke()
    let lineWidth = max(2, CGFloat(size) * 0.035)
    let left = NSPoint(x: CGFloat(size) * 0.30, y: CGFloat(size) * 0.55)
    let right = NSPoint(x: CGFloat(size) * 0.70, y: CGFloat(size) * 0.55)
    let center = NSPoint(x: CGFloat(size) * 0.50, y: CGFloat(size) * 0.33)
    for point in [left, right, center] {
        let circle = NSBezierPath(ovalIn: NSRect(x: point.x - CGFloat(size) * 0.095, y: point.y - CGFloat(size) * 0.095, width: CGFloat(size) * 0.19, height: CGFloat(size) * 0.19))
        circle.lineWidth = lineWidth
        circle.stroke()
    }
    let path = NSBezierPath()
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.move(to: left)
    path.line(to: center)
    path.line(to: right)
    path.stroke()

    NSColor(calibratedRed: 0.38, green: 0.90, blue: 0.63, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: CGFloat(size) * 0.65, y: CGFloat(size) * 0.69, width: CGFloat(size) * 0.16, height: CGFloat(size) * 0.16)).fill()
    return image
}

for item in sizes {
    let image = drawIcon(size: item.pixels)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("无法生成图标 PNG")
    }
    try png.write(to: iconset.appendingPathComponent(item.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fatalError("iconutil 生成 .icns 失败")
}
try? fileManager.removeItem(at: iconset)
