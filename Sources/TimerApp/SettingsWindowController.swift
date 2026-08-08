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
        if window == nil {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 700),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            created.title = "Einstellungen"
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        // Fresh view on every open so the stored values reload.
        window?.contentView = NSHostingView(rootView: SettingsView(
            preferences: preferences, focusMode: focusMode
        ))
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
