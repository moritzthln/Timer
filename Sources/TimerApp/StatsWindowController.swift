import AppKit
import SwiftUI
import TimerCore

struct StatsRootView: View {
    let stats: StatsStore
    let activity: ActivityStore

    @State private var tab = "fokus"

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $tab) {
                Text("Fokus").tag("fokus")
                Text("Aktivität").tag("aktivitaet")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if tab == "fokus" {
                StatsView(stats: stats)
            } else {
                ActivityView(store: activity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

final class StatsWindowController {
    private var window: NSWindow?
    private let stats: StatsStore
    private let activity: ActivityStore

    init(stats: StatsStore, activity: ActivityStore) {
        self.stats = stats
        self.activity = activity
    }

    func show() {
        if window == nil {
            // v8: freely resizable, 560×560 default, 480×460 minimum; size
            // and position persist via frame autosave.
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false
            )
            created.title = "Statistik"
            created.isReleasedWhenClosed = false
            created.contentMinSize = NSSize(width: 480, height: 460)
            created.center()
            // Restores a previously saved frame over the centered default.
            created.setFrameAutosaveName("StatsWindow")
            window = created
        }
        // Fresh view on every open so the numbers reload.
        window?.contentView = NSHostingView(rootView: StatsRootView(
            stats: stats, activity: activity
        ))
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
