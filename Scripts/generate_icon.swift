import AppKit

// Generates the app iconset. Usage: swift Scripts/generate_icon.swift <outDir>
let sizes: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
    (256, 1), (256, 2), (512, 1), (512, 2),
]
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for (points, scale) in sizes {
    let side = CGFloat(points * scale)
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()

    let inset = side * 0.09
    let rect = NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let background = NSBezierPath(roundedRect: rect, xRadius: side * 0.185, yRadius: side * 0.185)
    NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
    background.fill()

    let ringRect = rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.22)
    let ring = NSBezierPath(ovalIn: ringRect)
    ring.lineWidth = side * 0.045
    NSColor(calibratedWhite: 0.96, alpha: 1).setStroke()
    ring.stroke()

    let hand = NSBezierPath()
    hand.move(to: NSPoint(x: rect.midX, y: rect.midY))
    hand.line(to: NSPoint(x: rect.midX, y: ringRect.maxY - side * 0.02))
    hand.lineWidth = side * 0.045
    hand.lineCapStyle = .round
    hand.stroke()

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let name = scale == 1
        ? "icon_\(points)x\(points).png"
        : "icon_\(points)x\(points)@2x.png"
    try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("iconset written to \(outDir)")
