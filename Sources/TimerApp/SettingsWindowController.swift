import AppKit
import SwiftUI
import TimerCore

final class SettingsWindowController {
    private var window: NSWindow?
    private let preferences: Preferences
    private let focusMode: FocusModeController

    init(preferences: Preferences, focusMode: FocusModeController) {
        self.preferences = preferences
        self.focusMode = focusMode
    }

    func show() {
        let firstShow = window == nil
        if window == nil {
            let created = NSWindow(
                contentRect: .zero, // sized from the content by fitToContent
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            created.title = "Einstellungen"
            created.isReleasedWhenClosed = false
            window = created
        }
        guard let window else { return }
        // Fresh view on every open so the stored values reload (and the
        // v17 tab selection resets to Timer).
        window.contentView = NSHostingView(rootView: SettingsView(
            preferences: preferences, focusMode: focusMode
        ))
        fitToContent(window)
        if firstShow { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// v17: fixed window, derived size — the content (360 pt wide, as tall
    /// as the tallest settings tab) dictates the frame instead of a
    /// hardcoded height. Checked again one runloop turn later because the
    /// section lists load in onAppear, so the first pass can still see
    /// empty rows; a reopen keeps the window put (top-left anchored).
    private func fitToContent(_ window: NSWindow, retry: Bool = true) {
        guard let content = window.contentView else { return }
        window.layoutIfNeeded()
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(content.fittingSize)
        window.setFrameTopLeftPoint(topLeft)
        guard retry else { return }
        DispatchQueue.main.async { [weak self] in
            self?.fitToContent(window, retry: false)
        }
    }
}
