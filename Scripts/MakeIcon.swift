import AppKit
import Foundation

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./CodexUsage.iconset"
try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
_ = NSApplication.shared

let sizes: [(name: String, size: CGFloat)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for entry in sizes {
    let size = entry.size
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = bounds.insetBy(dx: size * 0.035, dy: size * 0.035)
    let corner = inset.width * 0.2237
    let shape = NSBezierPath(roundedRect: inset, xRadius: corner, yRadius: corner)
    shape.addClip()
    let top = NSColor(red: 0.36, green: 0.33, blue: 0.96, alpha: 1.0)
    let bottom = NSColor(red: 0.17, green: 0.60, blue: 0.87, alpha: 1.0)
    if let gradient = NSGradient(colors: [top, bottom]) {
        gradient.draw(in: inset, angle: -90)
    }

    if let symbol = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "Codex Usage") {
        let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .semibold)
        let configured = symbol.withSymbolConfiguration(configuration) ?? symbol
        let targetSize = configured.size
        let tinted = NSImage(size: targetSize)
        tinted.lockFocus()
        configured.draw(in: NSRect(origin: .zero, size: targetSize))
        NSColor.white.set()
        NSRect(origin: .zero, size: targetSize).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let origin = NSPoint(x: (size - targetSize.width) / 2, y: (size - targetSize.height) / 2)
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    }

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let representation = NSBitmapImageRep(data: tiff),
          let png = representation.representation(using: .png, properties: [:])
    else {
        fatalError("PNG encoding failed for \(entry.name)")
    }
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent("\(entry.name).png")
    try png.write(to: url)
    print("wrote \(url.path)")
}
