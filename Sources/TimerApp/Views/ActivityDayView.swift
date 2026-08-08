import SwiftUI
import TimerCore

/// The Tag mode of the Aktivität tab: date navigation, presence line, the
/// zoomable timeline (v9), and the per-day app list. App colors rank per day.
struct ActivityDayView: View {
    let store: ActivityStore
    let focusLog: FocusLog
    @Binding var day: Date

    @State private var summary: DaySummary?
    @State private var focusIntervals: [FocusInterval] = []
    /// Sparkline data: per-app seconds over the 7 days ending on `day`,
    /// loaded once per day navigation.
    @State private var sparkSeries: [String: [Double]] = [:]
    /// v10 drill-down; resets on date navigation and view switch (the mode
    /// switch rebuilds this view, so plain view state is exactly per-visit).
    @State private var selectedBundleID: String?

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
                presenceLine(summary)
                timeline(summary)
                ActivityAppListView(
                    apps: summary.apps,
                    sitesByBrowser: summary.sitesByBrowser,
                    colorFor: { colorFor(bundleID: $0, in: summary) },
                    sparkSeries: sparkSeries,
                    sparkHelp: "Letzte 7 Tage",
                    selectedBundleID: selectedBundleID,
                    onSelect: toggleSelection
                )
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
        summary = store.daySummary(for: day)
        focusIntervals = focusLog.intervals(onDay: day)
        let window = ((-6)...0).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: day)
        }
        sparkSeries = ActivitySparklineView.series(from: window.map(store.daySummary(for:)))
    }

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

    private func colorFor(bundleID: String, in summary: DaySummary) -> Color {
        let rank = summary.apps.firstIndex { $0.bundleID == bundleID }
            ?? ActivityPalette.colors.count - 1
        return ActivityPalette.color(rank: rank)
    }

    /// v9: the zoomable timeline lives in its own sub-view; the `.id(day)`
    /// tag gives it a fresh identity per date, so zoom resets to 1× on every
    /// date change (and on window reopen via the rebuilt view tree).
    private func timeline(_ summary: DaySummary) -> some View {
        Group {
            if let first = summary.firstActivity, let last = summary.lastActivity,
               last > first {
                ActivityTimelineView(
                    first: first, last: last, summary: summary,
                    colorFor: { colorFor(bundleID: $0, in: summary) },
                    selectedBundleID: selectedBundleID,
                    focusIntervals: focusIntervals
                )
                .id(day)
            }
        }
    }
}
