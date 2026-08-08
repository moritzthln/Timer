import SwiftUI
import TimerCore

/// Root of the Aktivität tab (v10): a Tag | Woche switcher over the day view
/// (v7–v9) and the new week view. Switcher state is per window session — the
/// stats window rebuilds its view tree on every open, so it defaults to Tag.
struct ActivityView: View {
    let store: ActivityStore
    let focusLog: FocusLog

    enum Mode {
        case day
        case week
    }

    @State private var mode: Mode = .day
    @State private var day = Date()
    @State private var weekAnchor = Date()

    private static let switcherHeight: CGFloat = 24

    /// Structural minimum of the tab, used for the shared stats window
    /// minimum: switcher + the taller of the two modes (both must fit at
    /// the window minimum) + footer (13) + the two 12 pt root gaps.
    static var minContentHeight: CGFloat {
        switcherHeight
            + max(ActivityDayView.minContentHeight, ActivityWeekView.minContentHeight)
            + 13 + 2 * 12
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $mode) {
                Text("Tag").tag(Mode.day)
                Text("Woche").tag(Mode.week)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(height: Self.switcherHeight)
            if mode == .day {
                ActivityDayView(store: store, focusLog: focusLog, day: $day)
            } else {
                ActivityWeekView(
                    store: store, focusLog: focusLog,
                    anchor: $weekAnchor, onOpenDay: openDay
                )
            }
            Text("Alle Daten bleiben lokal auf diesem Mac")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Week-row click: jump to that day's day view (fresh zoom via `.id(day)`).
    private func openDay(_ date: Date) {
        day = date
        mode = .day
    }
}
