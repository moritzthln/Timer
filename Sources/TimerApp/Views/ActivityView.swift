import SwiftUI
import TimerCore

/// Root of the Aktivität tab (v10): a Tag | Woche switcher over the day view
/// (v7–v9) and the new week view. Switcher state is per window session — the
/// stats window rebuilds its view tree on every open, so it defaults to Tag.
/// v12: the "Nur Fokus-Zeit" checkbox lives next to the switcher; its state
/// is per window session too and survives day/week navigation and switches.
struct ActivityView: View {
    let store: ActivityStore
    let focusLog: FocusLog
    var liveFocusStart: () -> Date? = { nil }
    /// v13: promoted websites shown as first-class rows (read live from
    /// Preferences by the app root).
    var promotedSites: () -> [String] = { [] }

    enum Mode {
        case day
        case week
    }

    @State private var mode: Mode = .day
    @State private var day = Date()
    @State private var weekAnchor = Date()
    @State private var focusOnly = false

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
            HStack(spacing: 12) {
                Picker("", selection: $mode) {
                    Text(tr("Tag", "Day")).tag(Mode.day)
                    Text(tr("Woche", "Week")).tag(Mode.week)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                focusOnlyToggle
            }
            .frame(height: Self.switcherHeight)
            if mode == .day {
                ActivityDayView(
                    store: store, focusLog: focusLog, liveFocusStart: liveFocusStart,
                    promotedSites: promotedSites, day: $day, focusOnly: focusOnly
                )
            } else {
                ActivityWeekView(
                    store: store, focusLog: focusLog, liveFocusStart: liveFocusStart,
                    promotedSites: promotedSites, anchor: $weekAnchor,
                    focusOnly: focusOnly, onOpenDay: openDay
                )
            }
            Text(tr("Alle Daten bleiben lokal auf diesem Mac", "All data stays local on this Mac"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// v12: small checkbox in the focus accent — everything in the tab then
    /// shows only what overlapped focus sessions.
    private var focusOnlyToggle: some View {
        Toggle(isOn: $focusOnly) {
            Text(tr("Nur Fokus-Zeit", "Focus time only")).font(.system(size: 11))
        }
        .toggleStyle(.checkbox)
        .tint(Color.accentColor)
        .foregroundStyle(focusOnly ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        .fixedSize()
        .help(tr("Nur Zeiten innerhalb von Fokus- und Pomodoro-Sessions zeigen", "Show only time inside focus and pomodoro sessions"))
    }

    /// Week-row click: jump to that day's day view (fresh zoom via `.id(day)`).
    private func openDay(_ date: Date) {
        day = date
        mode = .day
    }
}
