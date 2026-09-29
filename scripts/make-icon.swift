// Renders FinderPath's app icon and writes FinderPath/AppIcon.icns.
// Run from the repository root: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func render(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = size / canvas
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)

    // macOS icon grid: an 824 pt rounded square centred on the 1024 pt canvas, with a soft shadow.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.white.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.36, green: 0.72, blue: 1.0, alpha: 1),
               ending: NSColor(calibratedRed: 0.05, green: 0.38, blue: 0.93, alpha: 1))!
        .draw(in: shape, angle: -90)

    // A white folder with a path bar across it: the app's two halves, Finder and typing a path.
    // Drawn from shapes rather than an SF Symbol so it stays crisp at every size.
    let blue = NSColor(calibratedRed: 0.05, green: 0.38, blue: 0.93, alpha: 1)
    NSGraphicsContext.saveGraphicsState()
    let folderShadow = NSShadow()
    folderShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    folderShadow.shadowBlurRadius = 18
    folderShadow.shadowOffset = NSSize(width: 0, height: -8)
    folderShadow.set()
    NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 232, y: 560, width: 250, height: 120), xRadius: 40, yRadius: 40).fill()
    NSBezierPath(roundedRect: NSRect(x: 232, y: 300, width: 560, height: 330), xRadius: 48, yRadius: 48).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 232, y: 270, width: 560, height: 330), xRadius: 48, yRadius: 48).fill()

    let bar = NSRect(x: 280, y: 385, width: 464, height: 100)
    blue.setFill()
    NSBezierPath(roundedRect: bar, xRadius: 50, yRadius: 50).fill()
    let text = NSAttributedString(string: "~/", attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 70, weight: .bold),
        .foregroundColor: NSColor.white,
    ])
    text.draw(at: NSPoint(x: bar.minX + 44, y: bar.midY - text.size().height / 2))
    NSColor.white.setFill()
    NSRect(x: bar.minX + 44 + text.size().width + 12, y: bar.minY + 24, width: 9, height: bar.height - 48).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(size: CGFloat(points * factor)).write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "FinderPath/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try render(size: 512).write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-preview.png"))
print(iconutil.terminationStatus == 0 ? "Wrote FinderPath/AppIcon.icns" : "iconutil failed")
