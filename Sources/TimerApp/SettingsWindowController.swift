import AppKit
import SwiftUI
import TimerCore

final class SettingsWindowController {
    private var window: NSWindow?
    private let preferences: Preferences
    private let activity: ActivityStore
    private let focusMode: FocusModeController

    init(preferences: Preferences, activity: ActivityStore, focusMode: FocusModeController) {
        self.preferences = preferences
        self.activity = activity
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
        // Fresh view on every open so the category rows reload.
        window?.contentView = NSHostingView(rootView: SettingsView(
            preferences: preferences, activity: activity, focusMode: focusMode
        ))
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
