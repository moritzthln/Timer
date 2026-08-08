import AppKit
import SwiftUI
import TimerCore

struct StatsRootView: View {
    let stats: StatsStore
    let activity: ActivityStore
    let sessions: SessionStore
    let preferences: Preferences

    @State private var tab = "fokus"

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $tab) {
                Text("Fokus").tag("fokus")
                Text("Aktivität").tag("aktivitaet")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if tab == "fokus" {
                StatsView(stats: stats, sessions: sessions, preferences: preferences)
            } else {
                ActivityView(store: activity)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

final class StatsWindowController {
    private var window: NSWindow?
    private let stats: StatsStore
    private let activity: ActivityStore
    private let sessions: SessionStore
    private let preferences: Preferences

    init(stats: StatsStore, activity: ActivityStore, sessions: SessionStore, preferences: Preferences) {
        self.stats = stats
        self.activity = activity
        self.sessions = sessions
        self.preferences = preferences
    }

    func show() {
        if window == nil {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            created.title = "Statistik"
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        // Fresh view on every open so the numbers reload.
        window?.contentView = NSHostingView(rootView: StatsRootView(
            stats: stats, activity: activity, sessions: sessions, preferences: preferences
        ))
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
