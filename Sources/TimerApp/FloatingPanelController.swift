import AppKit
import Combine
import SwiftUI
import TimerCore

final class FloatingPanelController {
    private let panel: NSPanel
    private let engine: TimerEngine
    private let preferences: Preferences
    private var cancellable: AnyCancellable?

    init(engine: TimerEngine, preferences: Preferences) {
        self.engine = engine
        self.preferences = preferences

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 140, height: 64),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: FloatingView(engine: engine))
        hosting.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = hosting

        panel.setFrameAutosaveName("FloatingDisplay")

        cancellable = engine.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateVisibility() }
        }
        updateVisibility()
    }

    func updateVisibility() {
        let sessionActive: Bool
        switch engine.phase {
        case .running, .paused: sessionActive = true
        case .idle, .finished: sessionActive = false
        }
        let shouldShow = sessionActive && preferences.floatingEnabled
        if shouldShow && !panel.isVisible {
            ensureOnScreenPosition()
            panel.orderFrontRegardless()
        } else if !shouldShow && panel.isVisible {
            panel.orderOut(nil)
        }
    }

    /// Default: top-right under the menu bar; also rescues off-screen frames.
    private func ensureOnScreenPosition() {
        let visible = NSScreen.screens.contains {
            $0.visibleFrame.intersects(panel.frame)
        }
        let neverPositioned = panel.frame.origin == .zero
        guard neverPositioned || !visible, let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: area.maxX - panel.frame.width - 16,
            y: area.maxY - panel.frame.height - 8
        ))
    }
}
