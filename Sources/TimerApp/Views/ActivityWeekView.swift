import SwiftUI
import TimerCore

/// v10: the Woche mode of the Aktivität tab — ISO week navigation, seven
/// aligned day rows, week presence total, and the week-aggregated app list.
struct ActivityWeekView: View {
    let store: ActivityStore
    let focusLog: FocusLog
    var liveFocusStart: () -> Date? = { nil }
    /// v13: promoted websites shown as first-class rows (read live from
    /// Preferences by the app root).
    var promotedSites: () -> [String] = { [] }
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
        formatter.locale = L10n.locale
        formatter.dateFormat = tr("d.", "d")
        return formatter
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateFormat = tr("d. MMMM", "MMMM d")
        return formatter
    }()

    private var isCurrentWeek: Bool {
        WeekData.calendar.isDate(anchor, equalTo: Date(), toGranularity: .weekOfYear)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let data {
                // v13: one palette ranking over the promotion-applied raw
                // week totals — shared by the week rows and the list, stable
                // across the focus-filter toggle (v12 behavior).
                let ranks = SitePromotion.ranks(
                    apps: data.apps, sitesByBrowser: data.sitesByBrowser,
                    promoted: promotedSites()
                )
                let colorFor: (String) -> Color = {
                    ActivityPalette.color(rank: ranks[$0] ?? ActivityPalette.colors.count - 1)
                }
                // v11: fresh identity per displayed week, so the zoom
                // resets on week navigation (and on the Tag/Woche switch
                // plus window reopen via the rebuilt view tree).
                ActivityWeekTimelineView(
                    days: data.days,
                    colorFor: colorFor,
                    selectedBundleID: selectedBundleID,
                    promotedSites: promotedSites(),
                    focusOnly: focusOnly,
                    onOpenDay: onOpenDay
                )
                .id(weekStart)
                if data.hasActivity {
                    if focusOnly { focusLine(data) } else { presenceLine(data) }
                    if focusOnly, weekHasNoFocus(data) {
                        emptyFocusMessage
                    } else {
                        appList(data, colorFor: colorFor)
                    }
                } else {
                    Text(tr("Keine Daten für diese Woche", "No data for this week"))
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
        return tr("KW \(week) · \(rangeString)", "W\(week) · \(rangeString)")
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

    /// v19: promoted website rows select exactly like app rows — every week
    /// row draws that domain's site spans on top of its dimmed app segments.
    private func toggleSelection(_ bundleID: String) {
        selectedBundleID = selectedBundleID == bundleID ? nil : bundleID
    }

    // MARK: - Filtered values (v12) + promoted rows (v13)

    /// The app list over the promotion-applied week rows: promoted domains
    /// appear as their own entries, browsers show the remainder, and the
    /// cleansed disclosure map omits promoted domains.
    private func appList(
        _ data: WeekData, colorFor: @escaping (String) -> Color
    ) -> some View {
        let lists = SitePromotion.apply(
            apps: listApps(data), sitesByBrowser: listSites(data),
            promoted: promotedSites()
        )
        return ActivityAppListView(
            apps: lists.rows,
            sitesByBrowser: lists.sitesByBrowser,
            colorFor: colorFor,
            sparkSeries: sparkSeries,
            sparkHelp: rangeString,
            selectedBundleID: selectedBundleID,
            onSelect: toggleSelection,
            foldThreshold: focusOnly ? 10 : 60
        )
    }

    private func listApps(_ data: WeekData) -> [AppUsage] {
        focusOnly ? ActivityFocusFilter.apps(data.days) : data.apps
    }

    private func listSites(_ data: WeekData) -> [String: [SiteUsage]] {
        focusOnly ? ActivityFocusFilter.sites(data.days) : data.sitesByBrowser
    }

    /// Sparkline data over the displayed week's seven days (clipped to each
    /// day's focus intervals while the filter is on), overlaid with the
    /// promoted rows' series from the already-loaded per-day site segments.
    private var sparkSeries: [String: [Double]] {
        guard let data else { return [:] }
        let base = focusOnly
            ? ActivityFocusFilter.sparkSeries(
                summaries: data.days.map(\.summary), focus: data.days.map(\.focus)
            )
            : ActivitySparklineView.series(from: data.days.map(\.summary))
        return SitePromotion.sparkSeries(
            base: base,
            days: data.days.map {
                (siteSegments: $0.summary.siteSegments, clip: focusOnly ? $0.focus : nil)
            },
            promoted: promotedSites()
        )
    }

    private func weekHasNoFocus(_ data: WeekData) -> Bool {
        data.days.allSatisfy(\.focus.isEmpty)
    }

    /// v12 empty state: activity exists, focus does not — the week rows
    /// above stay (dimmed entirely) and this message replaces the app list.
    private var emptyFocusMessage: some View {
        Group {
            Text(tr("Keine Fokus-Sessions in diesem Zeitraum", "No focus sessions in this period"))
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
            Text(tr("Am PC", "At the Mac"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(tr("\(scopeLabel) · aktiv \(TimeFormatting.wording(seconds: data.presenceSeconds))", "\(scopeLabel) · active \(TimeFormatting.wording(seconds: data.presenceSeconds))"))
                .font(.system(size: 13, design: .monospaced))
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    /// v12: replaces the presence line while the filter is on — the sum of
    /// the seven days' focus intervals.
    private func focusLine(_ data: WeekData) -> some View {
        HStack {
            Text(tr("Fokus-Zeit", "Focus time"))
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
            ? tr("Diese Woche", "This week")
            : tr("KW \(WeekData.calendar.component(.weekOfYear, from: anchor))", "W\(WeekData.calendar.component(.weekOfYear, from: anchor))")
    }
}
