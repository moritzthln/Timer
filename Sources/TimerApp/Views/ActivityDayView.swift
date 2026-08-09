import SwiftUI
import TimerCore

/// The Tag mode of the Aktivität tab: date navigation, presence line, the
/// zoomable timeline (v9), and the per-day app list. App colors rank per day.
struct ActivityDayView: View {
    let store: ActivityStore
    let focusLog: FocusLog
    var liveFocusStart: () -> Date? = { nil }
    /// v13: promoted websites shown as first-class rows (read live from
    /// Preferences by the app root).
    var promotedSites: () -> [String] = { [] }
    @Binding var day: Date
    /// v12: the "Nur Fokus-Zeit" filter (owned by the tab root).
    let focusOnly: Bool

    /// The 7 window days ending on `day` (last = the displayed day):
    /// summaries and focus intervals, loaded once per day navigation — the
    /// data behind the list, the sparklines, and the clipped filter values.
    @State private var windowSummaries: [DaySummary] = []
    @State private var windowFocus: [[FocusInterval]] = []
    /// v10 drill-down; resets on date navigation and view switch (the mode
    /// switch rebuilds this view, so plain view state is exactly per-visit).
    @State private var selectedBundleID: String?

    private var summary: DaySummary? { windowSummaries.last }
    private var focusIntervals: [FocusInterval] { windowFocus.last ?? [] }

    /// Structural minimum of the day mode: header + presence line + fixed
    /// timeline + list minimum + three 12 pt gaps.
    static var minContentHeight: CGFloat {
        18 + 36 + ActivityTimelineView.totalHeight
            + ActivityAppListView.listMinHeight + 3 * 12
    }

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EE, d. MMMM"
        return formatter
    }()

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    private var isToday: Bool {
        Calendar.current.isDateInToday(day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let summary, summary.firstActivity != nil {
                // v13: one palette ranking over the promotion-applied raw day
                // rows — shared by the timeline and the list, stable across
                // the focus-filter toggle (v12 behavior).
                let ranks = SitePromotion.ranks(
                    apps: summary.apps, sitesByBrowser: summary.sitesByBrowser,
                    promoted: promotedSites()
                )
                let colorFor: (String) -> Color = {
                    ActivityPalette.color(rank: ranks[$0] ?? ActivityPalette.colors.count - 1)
                }
                if focusOnly { focusLine } else { presenceLine(summary) }
                timeline(summary, colorFor: colorFor)
                if focusOnly, focusIntervals.isEmpty {
                    emptyFocusMessage
                } else {
                    appList(summary, colorFor: colorFor)
                }
            } else {
                Text("Keine Daten für diesen Tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
                Spacer(minLength: 0)
            }
        }
        .onAppear(perform: reload)
    }

    // MARK: - Filtered values (v12) + promoted rows (v13)

    /// The app list over the promotion-applied rows: promoted domains appear
    /// as their own entries, browsers show the remainder, and the cleansed
    /// disclosure map omits promoted domains.
    private func appList(
        _ summary: DaySummary, colorFor: @escaping (String) -> Color
    ) -> some View {
        let lists = SitePromotion.apply(
            apps: listApps(summary), sitesByBrowser: listSites(summary),
            promoted: promotedSites()
        )
        return ActivityAppListView(
            apps: lists.rows,
            sitesByBrowser: lists.sitesByBrowser,
            colorFor: colorFor,
            sparkSeries: sparkSeries,
            sparkHelp: "Letzte 7 Tage",
            selectedBundleID: selectedBundleID,
            onSelect: toggleSelection,
            foldThreshold: focusOnly ? 10 : 60
        )
    }

    private func listApps(_ summary: DaySummary) -> [AppUsage] {
        focusOnly
            ? ActivityFocusFilter.apps(summary, intervals: focusIntervals)
            : summary.apps
    }

    private func listSites(_ summary: DaySummary) -> [String: [SiteUsage]] {
        focusOnly
            ? ActivityFocusFilter.sites(summary, intervals: focusIntervals)
            : summary.sitesByBrowser
    }

    /// Sparkline data: per-app seconds over the 7 window days (clipped to
    /// focus intervals while the filter is on), overlaid with the promoted
    /// rows' series from the already-loaded per-day site segments.
    private var sparkSeries: [String: [Double]] {
        let base = focusOnly
            ? ActivityFocusFilter.sparkSeries(summaries: windowSummaries, focus: windowFocus)
            : ActivitySparklineView.series(from: windowSummaries)
        return SitePromotion.sparkSeries(
            base: base,
            days: windowSummaries.enumerated().map { index, summary in
                (
                    siteSegments: summary.siteSegments,
                    clip: focusOnly
                        ? (index < windowFocus.count ? windowFocus[index] : [])
                        : nil
                )
            },
            promoted: promotedSites()
        )
    }

    /// v12 empty state: activity exists, focus does not — the timeline above
    /// stays (dimmed entirely) and this message replaces the app list.
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

    private var header: some View {
        HStack {
            Button("‹") { shift(by: -1) }.buttonStyle(.plain)
            Spacer()
            Text(Self.titleFormatter.string(from: day))
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button("›") { shift(by: 1) }
                .buttonStyle(.plain)
                .disabled(isToday)
                .foregroundStyle(isToday ? .tertiary : .primary)
        }
    }

    private func shift(by days: Int) {
        guard let shifted = Calendar.current.date(byAdding: .day, value: days, to: day) else { return }
        day = min(shifted, Date())
        selectedBundleID = nil
        reload()
    }

    private func reload() {
        let window = ((-6)...0).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: day)
        }
        windowSummaries = window.map(store.daySummary(for:))
        let liveStart = liveFocusStart()
        windowFocus = window.map {
            LiveFocus.augment(focusLog.intervals(onDay: $0), onDay: $0, liveStart: liveStart)
        }
    }

    /// v19: promoted website rows select exactly like app rows — the timeline
    /// draws that domain's site spans on top of the dimmed app segments.
    private func toggleSelection(_ bundleID: String) {
        selectedBundleID = selectedBundleID == bundleID ? nil : bundleID
    }

    private func presenceLine(_ summary: DaySummary) -> some View {
        HStack {
            Text("Am PC")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let first = summary.firstActivity, let last = summary.lastActivity {
                Text("\(Self.hourFormatter.string(from: first)) – \(Self.hourFormatter.string(from: last)) · aktiv \(TimeFormatting.wording(seconds: summary.presenceSeconds))")
                    .font(.system(size: 13, design: .monospaced))
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    /// v12: replaces the presence line while the filter is on — the sum of
    /// the day's focus intervals.
    private var focusLine: some View {
        HStack {
            Text("Fokus-Zeit")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(TimeFormatting.wording(
                seconds: ActivityFocusFilter.focusSeconds(focusIntervals)
            ))
            .font(.system(size: 13, design: .monospaced))
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    /// v9: the zoomable timeline lives in its own sub-view; the `.id(day)`
    /// tag gives it a fresh identity per date, so zoom resets to 1× on every
    /// date change (and on window reopen via the rebuilt view tree).
    private func timeline(
        _ summary: DaySummary, colorFor: @escaping (String) -> Color
    ) -> some View {
        Group {
            if let first = summary.firstActivity, let last = summary.lastActivity,
               last > first {
                ActivityTimelineView(
                    first: first, last: last, summary: summary,
                    colorFor: colorFor,
                    selectedBundleID: selectedBundleID,
                    promotedSites: promotedSites(),
                    focusIntervals: focusIntervals,
                    focusOnly: focusOnly
                )
                .id(day)
            }
        }
    }
}
