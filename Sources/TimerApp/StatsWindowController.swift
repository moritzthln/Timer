import AppKit
import SwiftUI
import TimerCore

final class StatsWindowController {
    private var window: NSWindow?
    private let stats: StatsStore

    init(stats: StatsStore) {
        self.stats = stats
    }

    func show() {
        if window == nil {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 240),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            created.title = "Statistik"
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        // Fresh view on every open so the numbers reload.
        window?.contentView = NSHostingView(rootView: StatsView(stats: stats))
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
