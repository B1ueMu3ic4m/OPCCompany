import AppKit
import Foundation

let root = CommandLine.arguments.dropFirst().first.map(URL.init(fileURLWithPath:))
    ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assetsURL = root.appendingPathComponent("Assets", isDirectory: true)
let iconsetURL = assetsURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = assetsURL.appendingPathComponent("AppIcon.icns")

try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let iconFiles: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for icon in iconFiles {
    let image = NSImage(size: NSSize(width: icon.pixels, height: icon.pixels))
    image.lockFocus()
    drawIcon(in: NSRect(x: 0, y: 0, width: icon.pixels, height: icon.pixels), scale: CGFloat(icon.pixels) / 1024.0)
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render \(icon.name)")
    }
    try png.write(to: iconsetURL.appendingPathComponent(icon.name), options: .atomic)
}

try writeICNS(to: icnsURL, iconsetURL: iconsetURL)

private func drawIcon(in rect: NSRect, scale: CGFloat) {
    let bounds = rect
    let radius = 210 * scale

    NSGraphicsContext.current?.imageInterpolation = .high

    let basePath = NSBezierPath(roundedRect: bounds.insetBy(dx: 42 * scale, dy: 42 * scale), xRadius: radius, yRadius: radius)
    NSGradient(colors: [
        NSColor(red: 0.965, green: 0.982, blue: 0.990, alpha: 1),
        NSColor(red: 0.720, green: 0.790, blue: 0.820, alpha: 1),
        NSColor(red: 0.060, green: 0.078, blue: 0.095, alpha: 1)
    ])?.draw(in: basePath, angle: 38)

    NSColor(red: 0.030, green: 0.050, blue: 0.065, alpha: 0.32).setStroke()
    basePath.lineWidth = 5 * scale
    basePath.stroke()

    let slab = NSBezierPath(roundedRect: NSRect(x: bounds.midX - 300 * scale, y: bounds.midY - 255 * scale, width: 600 * scale, height: 510 * scale), xRadius: 88 * scale, yRadius: 88 * scale)
    let transform = AffineTransform(translationByX: bounds.midX, byY: bounds.midY)
    slab.transform(using: transform.inverted()!)
    slab.transform(using: AffineTransform(rotationByDegrees: -8))
    slab.transform(using: transform)
    NSGradient(colors: [
        NSColor(red: 0.025, green: 0.040, blue: 0.055, alpha: 0.98),
        NSColor(red: 0.105, green: 0.145, blue: 0.165, alpha: 0.96)
    ])?.draw(in: slab, angle: -30)
    NSColor(red: 0.00, green: 0.64, blue: 0.78, alpha: 0.45).setStroke()
    slab.lineWidth = 6 * scale
    slab.stroke()

    let center = NSPoint(x: bounds.midX, y: bounds.midY + 28 * scale)
    let outerRing = NSBezierPath(ovalIn: NSRect(x: center.x - 178 * scale, y: center.y - 178 * scale, width: 356 * scale, height: 356 * scale))
    NSColor(red: 0.00, green: 0.64, blue: 0.78, alpha: 0.18).setStroke()
    outerRing.lineWidth = 42 * scale
    outerRing.stroke()

    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: 178 * scale, startAngle: 212, endAngle: 78, clockwise: false)
    NSColor(red: 0.00, green: 0.70, blue: 0.86, alpha: 0.98).setStroke()
    arc.lineWidth = 46 * scale
    arc.lineCapStyle = .round
    arc.stroke()

    let commandLine = NSBezierPath()
    commandLine.move(to: NSPoint(x: center.x - 235 * scale, y: center.y - 136 * scale))
    commandLine.line(to: NSPoint(x: center.x - 58 * scale, y: center.y - 38 * scale))
    commandLine.line(to: NSPoint(x: center.x + 136 * scale, y: center.y - 152 * scale))
    commandLine.line(to: NSPoint(x: center.x + 244 * scale, y: center.y + 78 * scale))
    NSColor.white.withAlphaComponent(0.50).setStroke()
    commandLine.lineWidth = 10 * scale
    commandLine.lineCapStyle = .round
    commandLine.lineJoinStyle = .round
    commandLine.stroke()

    drawNode(at: NSPoint(x: center.x - 235 * scale, y: center.y - 136 * scale), radius: 42 * scale, fill: NSColor(red: 0.00, green: 0.64, blue: 0.78, alpha: 1))
    drawNode(at: NSPoint(x: center.x - 58 * scale, y: center.y - 38 * scale), radius: 34 * scale, fill: NSColor.white.withAlphaComponent(0.96))
    drawNode(at: NSPoint(x: center.x + 136 * scale, y: center.y - 152 * scale), radius: 38 * scale, fill: NSColor(red: 0.13, green: 0.76, blue: 0.50, alpha: 1))
    drawNode(at: NSPoint(x: center.x + 244 * scale, y: center.y + 78 * scale), radius: 50 * scale, fill: NSColor(red: 1.00, green: 0.64, blue: 0.22, alpha: 1))

    let core = NSBezierPath(ovalIn: NSRect(x: center.x - 82 * scale, y: center.y + 118 * scale, width: 164 * scale, height: 164 * scale))
    NSColor(red: 1.00, green: 0.64, blue: 0.22, alpha: 0.16).setFill()
    NSBezierPath(ovalIn: core.bounds.insetBy(dx: -42 * scale, dy: -42 * scale)).fill()
    NSGradient(colors: [
        NSColor(red: 1.00, green: 0.74, blue: 0.30, alpha: 1),
        NSColor(red: 1.00, green: 0.44, blue: 0.22, alpha: 1)
    ])?.draw(in: core, angle: -45)

    let mark = NSBezierPath()
    mark.move(to: NSPoint(x: bounds.midX - 148 * scale, y: bounds.minY + 194 * scale))
    mark.line(to: NSPoint(x: bounds.midX - 34 * scale, y: bounds.minY + 130 * scale))
    mark.line(to: NSPoint(x: bounds.midX + 148 * scale, y: bounds.minY + 214 * scale))
    NSColor(red: 0.025, green: 0.040, blue: 0.055, alpha: 0.85).setStroke()
    mark.lineWidth = 24 * scale
    mark.lineCapStyle = .round
    mark.lineJoinStyle = .round
    mark.stroke()
}

private func drawNode(at point: NSPoint, radius: CGFloat, fill: NSColor) {
    NSColor.black.withAlphaComponent(0.18).setFill()
    NSBezierPath(ovalIn: NSRect(x: point.x - radius * 1.25, y: point.y - radius * 1.25, width: radius * 2.5, height: radius * 2.5)).fill()
    fill.setFill()
    NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)).fill()
}

private func writeICNS(to outputURL: URL, iconsetURL: URL) throws {
    let entries: [(type: String, file: String)] = [
        ("icp4", "icon_16x16.png"),
        ("icp5", "icon_32x32.png"),
        ("icp6", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"),
        ("ic08", "icon_256x256.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png")
    ]

    var body = Data()
    for entry in entries {
        let png = try Data(contentsOf: iconsetURL.appendingPathComponent(entry.file))
        body.appendFourCC(entry.type)
        body.appendUInt32BE(UInt32(png.count + 8))
        body.append(png)
    }

    var icns = Data()
    icns.appendFourCC("icns")
    icns.appendUInt32BE(UInt32(body.count + 8))
    icns.append(body)
    try icns.write(to: outputURL, options: .atomic)
}

private extension Data {
    mutating func appendFourCC(_ value: String) {
        append(contentsOf: value.utf8.prefix(4))
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }
}
