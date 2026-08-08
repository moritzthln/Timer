import SwiftUI
import TimerCore

/// v10: the Woche mode of the Aktivität tab — ISO week navigation, seven
/// aligned day rows, week presence total, and the week-aggregated app list.
struct ActivityWeekView: View {
    let store: ActivityStore
    @Binding var anchor: Date
    let onOpenDay: (Date) -> Void

    @State private var data: WeekData?

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
                ActivityWeekTimelineView(
                    days: data.days,
                    colorFor: color(for:),
                    onOpenDay: onOpenDay
                )
                if data.hasActivity {
                    presenceLine(data)
                    ActivityAppListView(
                        apps: data.apps,
                        sitesByBrowser: data.sitesByBrowser,
                        colorFor: color(for:)
                    )
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

    /// "KW 32 · 4.–10. August" (month spelled once inside one month,
    /// twice across a month boundary).
    private var title: String {
        let calendar = WeekData.calendar
        let start = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let week = calendar.component(.weekOfYear, from: start)
        let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
        let range = sameMonth
            ? "\(Self.dayFormatter.string(from: start))–\(Self.dayMonthFormatter.string(from: end))"
            : "\(Self.dayMonthFormatter.string(from: start)) – \(Self.dayMonthFormatter.string(from: end))"
        return "KW \(week) · \(range)"
    }

    private func shift(byWeeks weeks: Int) {
        guard let shifted = WeekData.calendar.date(
            byAdding: .day, value: weeks * 7, to: anchor
        ) else { return }
        anchor = min(shifted, Date())
        reload()
    }

    private func reload() {
        data = WeekData.load(store: store, weekOf: anchor)
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
