import AppKit

/// Renders the idle menu bar icon: the `timer` symbol centered inside a thin
/// goal-progress arc, as an 18×18 pt template image. The arc runs clockwise
/// from 12 o'clock; a full circle means the daily goal is reached. A faint
/// full track keeps the ring legible at 0 %.
enum MenuBarRingRenderer {
    private static let side: CGFloat = 18
    private static let lineWidth: CGFloat = 1.5

    /// `progress` is today's focus seconds vs. the goal; clamped to 0...1.
    static func image(progress: Double) -> NSImage {
        let clamped = max(0, min(1, progress))
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            drawSymbol(in: rect)
            drawRing(progress: clamped, in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawSymbol(in rect: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "timer", accessibilityDescription: "Timer")?
            .withSymbolConfiguration(config) else { return }
        let size = symbol.size
        symbol.draw(in: NSRect(
            x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
            width: size.width, height: size.height
        ))
    }

    private static func drawRing(progress: Double, in rect: NSRect) {
        let radius = rect.width / 2 - lineWidth / 2
        let center = NSPoint(x: rect.midX, y: rect.midY)

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        NSColor.black.withAlphaComponent(0.2).setStroke()
        track.stroke()

        guard progress > 0 else { return }
        let arc = NSBezierPath()
        if progress >= 1 {
            arc.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        } else {
            // Clockwise from 12 o'clock (90° in unflipped AppKit coordinates).
            arc.appendArc(
                withCenter: center, radius: radius,
                startAngle: 90, endAngle: 90 - progress * 360, clockwise: true
            )
        }
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        NSColor.black.setStroke()
        arc.stroke()
    }
}
