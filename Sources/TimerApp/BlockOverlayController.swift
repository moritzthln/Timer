import AppKit
import SwiftUI

/// Small top-center "Geblockt: …" toast; auto-hides after 2.5 s.
final class BlockOverlayController {
    private let panel: NSPanel
    private var hideTimer: Foundation.Timer?
    private var lastShown: [String: Date] = [:]

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 44),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
    }

    /// Shows the toast unless this target was announced within the last 10 s.
    func show(blocked name: String) {
        show(text: "Geblockt: \(name)", throttleKey: name)
    }

    /// v15 allowlist wording, same per-target throttle.
    func show(notAllowed name: String) {
        show(text: "Nicht erlaubt: \(name)", throttleKey: name)
    }

    private func show(text: String, throttleKey: String) {
        let nowDate = Date()
        if let last = lastShown[throttleKey], nowDate.timeIntervalSince(last) < 10 { return }
        lastShown[throttleKey] = nowDate

        let view = Text(text)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 260, height: 44)
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: area.midX - panel.frame.width / 2,
                y: area.maxY - panel.frame.height - 12
            ))
        }
        panel.orderFrontRegardless()

        hideTimer?.invalidate()
        hideTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.panel.orderOut(nil)
        }
    }
}
