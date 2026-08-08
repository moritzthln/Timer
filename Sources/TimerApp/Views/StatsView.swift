import SwiftUI
import TimerCore

struct StatsView: View {
    let stats: StatsStore

    @State private var today: Double = 0
    @State private var week: Double = 0
    @State private var allTime: Double = 0
    @State private var activeDays: Int = 0
    @State private var days: [DayStat] = []
    @State private var heatWeeks: [[HeatmapView.Day]] = []

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    // v9: real content minimums. The GeometryReader hides the children's
    // intrinsic minimums from the window sizing, so the tab declares its
    // combined minimum explicitly: metric tiles (caption + title2 value +
    // 2 x 14 pt padding ≈ 68 pt), the fixed-height chart, the heatmap at
    // its minimum cell size, and the two 18 pt gaps between the blocks.
    private static let metricRowMinHeight: CGFloat = 68
    // v14: below this available width the four tiles wrap 2×2 — one-row
    // tiles narrower than ~110 pt would scale their values illegibly
    // (4 × 110 + 3 × 12 spacing ≈ 480).
    private static let tileWrapWidth: CGFloat = 480
    // v14: at the window minimum width the tiles are wrapped, so the height
    // minimum covers two tile rows plus their 12 pt gap. The shared stats
    // window minimum still comes from the taller Aktivität tab.
    private static let metricBlockMinHeight: CGFloat = 2 * metricRowMinHeight + 12
    private static let blockSpacing: CGFloat = 18
    private static let chartHeight: CGFloat = 200
    static var minContentSize: CGSize {
        CGSize(
            width: HeatmapView.minSize.width,
            height: metricBlockMinHeight + 2 * blockSpacing + chartHeight
                + HeatmapView.minSize.height
        )
    }

    var body: some View {
        // v8: the window is resizable — every block derives its width from
        // the available space instead of fixed frames.
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: Self.blockSpacing) {
                metricRow(width: geo.size.width)
                chart
                HeatmapView(weeks: heatWeeks, width: geo.size.width)
                Spacer(minLength: 0)
            }
        }
        .frame(minWidth: Self.minContentSize.width, minHeight: Self.minContentSize.height)
        .onAppear(perform: reload)
    }

    // MARK: - Metric tiles

    /// v14: four tiles — Heute · Diese Woche · Gesamt · Ø pro Tag. One row
    /// at the 560 pt default; near the window minimum they wrap 2×2.
    private func metricRow(width: CGFloat) -> some View {
        Group {
            if width < Self.tileWrapWidth {
                VStack(spacing: 12) {
                    HStack(spacing: 12) { todayTile; weekTile }
                    HStack(spacing: 12) { allTimeTile; averageTile }
                }
            } else {
                HStack(spacing: 12) { todayTile; weekTile; allTimeTile; averageTile }
            }
        }
    }

    private var todayTile: some View {
        metricTile(title: "Heute", text: TimeFormatting.wording(seconds: today))
    }

    private var weekTile: some View {
        metricTile(title: "Diese Woche", text: TimeFormatting.wording(seconds: week))
    }

    private var allTimeTile: some View {
        metricTile(title: "Gesamt", text: TimeFormatting.wording(seconds: allTime))
    }

    /// All-time seconds over days with focus time; "–" before the first one.
    private var averageTile: some View {
        metricTile(
            title: "Ø pro Tag",
            text: activeDays > 0
                ? TimeFormatting.wording(seconds: allTime / Double(activeDays))
                : "–"
        )
        .help("Durchschnitt über Tage mit Fokus-Zeit")
    }

    private func metricTile(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            // One line always: long values (a large "Gesamt") scale down a
            // little instead of wrapping and breaking the 68 pt tile height.
            Text(text)
                .font(.system(.title2, design: .monospaced).weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 7-day chart (v8: 160 pt, minute value above each bar)

    private var chart: some View {
        let maxSeconds = max(days.map(\.seconds).max() ?? 0, 60)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                chartBar(day: day, isToday: index == days.count - 1, maxSeconds: maxSeconds)
            }
        }
        .frame(height: Self.chartHeight, alignment: .bottom)
    }

    private func chartBar(day: DayStat, isToday: Bool, maxSeconds: Double) -> some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            Text("\(Int(day.seconds / 60))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isToday ? .primary : .secondary)
            Rectangle()
                .fill(isToday ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(height: max(3, 160 * day.seconds / maxSeconds))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(Self.weekdayFormatter.string(from: day.date))
                .font(.system(size: 11))
                .foregroundStyle(isToday ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    private func reload() {
        today = stats.todaySeconds()
        week = stats.weekSeconds()
        allTime = stats.allTimeSeconds()
        activeDays = stats.activeDayCount()
        days = stats.last7Days()
        heatWeeks = HeatmapView.build(now: Date()) { stats.seconds(onDayOf: $0) }
    }
}
