import SwiftUI
import TimerCore

/// v10: the Woche mode of the Aktivität tab — ISO week navigation, seven
/// aligned day rows, week presence total, and the week-aggregated app list.
struct ActivityWeekView: View {
    let store: ActivityStore
    let focusLog: FocusLog
    var liveFocusStart: () -> Date? = { nil }
    @Binding var anchor: Date
    /// v12: the "Nur Fokus-Zeit" filter (owned by the tab root).
    let focusOnly: Bool
    let onOpenDay: (Date) -> Void

    @State private var data: WeekData?
    /// v10 drill-down; resets on week navigation and view switch (the mode
    /// switch rebuilds this view, so plain view state is exactly per-visit).
    @State private var selectedBundleID: String?

    /// Structural minimum of the week mode: header + week rows block +
    /// presence line + list minimum + three 12 pt gaps.
    static var minContentHeight: CGFloat {
        18 + ActivityWeekTimelineView.minHeight + 36
            + ActivityAppListView.listMinHeight + 3 * 12
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d."
        return formatter
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d. MMMM"
        return formatter
    }()

    private var isCurrentWeek: Bool {
        WeekData.calendar.isDate(anchor, equalTo: Date(), toGranularity: .weekOfYear)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let data {
                // v11: fresh identity per displayed week, so the zoom
                // resets on week navigation (and on the Tag/Woche switch
                // plus window reopen via the rebuilt view tree).
                ActivityWeekTimelineView(
                    days: data.days,
                    colorFor: color(for:),
                    selectedBundleID: selectedBundleID,
                    focusOnly: focusOnly,
                    onOpenDay: onOpenDay
                )
                .id(weekStart)
                if data.hasActivity {
                    if focusOnly { focusLine(data) } else { presenceLine(data) }
                    if focusOnly, weekHasNoFocus(data) {
                        emptyFocusMessage
                    } else {
                        ActivityAppListView(
                            apps: listApps(data),
                            sitesByBrowser: listSites(data),
                            colorFor: color(for:),
                            sparkSeries: sparkSeries,
                            sparkHelp: rangeString,
                            selectedBundleID: selectedBundleID,
                            onSelect: toggleSelection
                        )
                    }
                } else {
                    Text("Keine Daten für diese Woche")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 30)
                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear(perform: reload)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("‹") { shift(byWeeks: -1) }.buttonStyle(.plain)
            Spacer()
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button("›") { shift(byWeeks: 1) }
                .buttonStyle(.plain)
                .disabled(isCurrentWeek)
                .foregroundStyle(isCurrentWeek ? .tertiary : .primary)
        }
    }

    /// "KW 32 · 4.–10. August".
    private var title: String {
        let week = WeekData.calendar.component(.weekOfYear, from: weekStart)
        return "KW \(week) · \(rangeString)"
    }

    private var weekStart: Date {
        WeekData.calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
    }

    /// "4.–10. August" — the month is spelled once inside one month, twice
    /// across a month boundary. Also the week sparklines' tooltip.
    private var rangeString: String {
        let start = weekStart
        let end = WeekData.calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let sameMonth = WeekData.calendar.isDate(start, equalTo: end, toGranularity: .month)
        return sameMonth
            ? "\(Self.dayFormatter.string(from: start))–\(Self.dayMonthFormatter.string(from: end))"
            : "\(Self.dayMonthFormatter.string(from: start)) – \(Self.dayMonthFormatter.string(from: end))"
    }

    private func shift(byWeeks weeks: Int) {
        guard let shifted = WeekData.calendar.date(
            byAdding: .day, value: weeks * 7, to: anchor
        ) else { return }
        anchor = min(shifted, Date())
        selectedBundleID = nil
        reload()
    }

    private func reload() {
        data = WeekData.load(
            store: store, focusLog: focusLog, weekOf: anchor,
            liveFocusStart: liveFocusStart()
        )
    }

    private func toggleSelection(_ bundleID: String) {
        selectedBundleID = selectedBundleID == bundleID ? nil : bundleID
    }

    // MARK: - Filtered values (v12)

    private func listApps(_ data: WeekData) -> [AppUsage] {
        focusOnly ? ActivityFocusFilter.apps(data.days) : data.apps
    }

    private func listSites(_ data: WeekData) -> [String: [SiteUsage]] {
        focusOnly ? ActivityFocusFilter.sites(data.days) : data.sitesByBrowser
    }

    /// Sparkline data over the displayed week's seven days (clipped to each
    /// day's focus intervals while the filter is on).
    private var sparkSeries: [String: [Double]] {
        guard let data else { return [:] }
        return focusOnly
            ? ActivityFocusFilter.sparkSeries(
                summaries: data.days.map(\.summary), focus: data.days.map(\.focus)
            )
            : ActivitySparklineView.series(from: data.days.map(\.summary))
    }

    private func weekHasNoFocus(_ data: WeekData) -> Bool {
        data.days.allSatisfy(\.focus.isEmpty)
    }

    /// v12 empty state: activity exists, focus does not — the week rows
    /// above stay (dimmed entirely) and this message replaces the app list.
    private var emptyFocusMessage: some View {
        Group {
            Text("Keine Fokus-Sessions in diesem Zeitraum")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 30)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Content

    private func presenceLine(_ data: WeekData) -> some View {
        HStack {
            Text("Am PC")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(scopeLabel) · aktiv \(TimeFormatting.wording(seconds: data.presenceSeconds))")
                .font(.system(size: 13, design: .monospaced))
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    /// v12: replaces the presence line while the filter is on — the sum of
    /// the seven days' focus intervals.
    private func focusLine(_ data: WeekData) -> some View {
        HStack {
            Text("Fokus-Zeit")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(TimeFormatting.wording(seconds: data.days.reduce(0) {
                $0 + ActivityFocusFilter.focusSeconds($1.focus)
            }))
            .font(.system(size: 13, design: .monospaced))
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    /// Past weeks say "KW 31" instead of a wrong "Diese Woche".
    private var scopeLabel: String {
        isCurrentWeek
            ? "Diese Woche"
            : "KW \(WeekData.calendar.component(.weekOfYear, from: anchor))"
    }

    private func color(for bundleID: String) -> Color {
        ActivityPalette.color(rank: data?.ranks[bundleID] ?? ActivityPalette.colors.count - 1)
    }
}
