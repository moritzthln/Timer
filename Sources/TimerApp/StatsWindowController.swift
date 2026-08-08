import AppKit
import SwiftUI
import TimerCore

struct StatsRootView: View {
    let stats: StatsStore
    let activity: ActivityStore
    let focusLog: FocusLog
    var liveFocusStart: () -> Date? = { nil }

    @State private var tab = "fokus"

    /// v9: one shared tab minimum — the larger of the two tabs — so the
    /// window minimum does not change when switching tabs; a window sized
    /// at the minimum stays fully visible on both.
    private static var tabMinSize: CGSize {
        CGSize(
            width: StatsView.minContentSize.width,
            height: max(StatsView.minContentSize.height, ActivityView.minContentHeight)
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $tab) {
                Text("Fokus").tag("fokus")
                Text("Aktivität").tag("aktivitaet")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Group {
                if tab == "fokus" {
                    StatsView(stats: stats)
                } else {
                    ActivityView(store: activity, focusLog: focusLog, liveFocusStart: liveFocusStart)
                }
            }
            .frame(minWidth: Self.tabMinSize.width, minHeight: Self.tabMinSize.height)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

final class StatsWindowController {
    private var window: NSWindow?
    private let stats: StatsStore
    private let activity: ActivityStore
    private let focusLog: FocusLog
    private let liveFocusStart: () -> Date?

    init(stats: StatsStore, activity: ActivityStore, focusLog: FocusLog,
         liveFocusStart: @escaping () -> Date?) {
        self.stats = stats
        self.activity = activity
        self.focusLog = focusLog
        self.liveFocusStart = liveFocusStart
    }

    func show() {
        if window == nil {
            // v8: freely resizable, 560×560 default; size and position
            // persist via frame autosave. v9: the minimum is derived from
            // the content (sizingOptions below), no hardcoded contentMinSize.
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false
            )
            created.title = "Statistik"
            created.isReleasedWhenClosed = false
            created.center()
            // Restores a previously saved frame over the centered default.
            created.setFrameAutosaveName("StatsWindow")
            window = created
        }
        guard let window else { return }
        // Fresh hosting controller on every open so the numbers reload (and
        // the v9 timeline zoom resets). Assigning contentViewController lets
        // AppKit resize the window to the view's size — keep the user's
        // frame by restoring it right after.
        let frame = window.frame
        let hosting = NSHostingController(rootView: StatsRootView(
            stats: stats, activity: activity, focusLog: focusLog,
            liveFocusStart: liveFocusStart
        ))
        // v9: propagates the SwiftUI minimum size to window.contentMinSize —
        // the window shrinks exactly to where everything still fits, never past.
        hosting.sizingOptions = [.minSize]
        window.contentViewController = hosting
        window.setFrame(frame, display: false)
        growToMinimumIfNeeded(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// A frame autosaved before v9 may be smaller than the content-derived
    /// minimum; `contentMinSize` only blocks user resizing, so such a window
    /// is grown to the minimum once on open (top-left anchored). Checked
    /// again one runloop turn later in case the hosting controller publishes
    /// the minimum only after the first layout pass.
    private func growToMinimumIfNeeded(_ window: NSWindow, retry: Bool = true) {
        window.layoutIfNeeded()
        let minSize = window.contentMinSize
        let content = window.contentRect(forFrameRect: window.frame).size
        if content.width < minSize.width || content.height < minSize.height {
            let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            window.setContentSize(NSSize(
                width: max(content.width, minSize.width),
                height: max(content.height, minSize.height)
            ))
            window.setFrameTopLeftPoint(topLeft)
        }
        guard retry else { return }
        DispatchQueue.main.async { [weak self] in
            self?.growToMinimumIfNeeded(window, retry: false)
        }
    }
}
