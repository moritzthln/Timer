import SwiftUI
import TimerCore

struct StatsView: View {
    let stats: StatsStore

    @State private var today: Double = 0
    @State private var week: Double = 0
    @State private var days: [DayStat] = []
    @State private var heatWeeks: [[HeatmapView.Day]] = []

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    var body: some View {
        // v8: the window is resizable — every block derives its width from
        // the available space instead of fixed frames.
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 18) {
                metricRow
                chart
                HeatmapView(weeks: heatWeeks, width: geo.size.width)
                Spacer(minLength: 0)
            }
        }
        .onAppear(perform: reload)
    }

    // MARK: - Metric tiles

    private var metricRow: some View {
        HStack(spacing: 12) {
            metricTile(title: "Heute", value: today)
            metricTile(title: "Diese Woche", value: week)
        }
    }

    private func metricTile(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(TimeFormatting.wording(seconds: value))
                .font(.system(.title2, design: .monospaced).weight(.medium))
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
        .frame(height: 200, alignment: .bottom)
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
        days = stats.last7Days()
        heatWeeks = HeatmapView.build(now: Date()) { stats.seconds(onDayOf: $0) }
    }
}
