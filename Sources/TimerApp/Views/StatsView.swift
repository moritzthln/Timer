import SwiftUI
import TimerCore

struct StatsView: View {
    let stats: StatsStore
    let preferences: Preferences

    @State private var today: Double = 0
    @State private var week: Double = 0
    @State private var days: [DayStat] = []
    @State private var streak = 0
    @State private var heatWeeks: [[GoalHeatmapView.Day]] = []

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            metricRow
            chart
            GoalHeatmapView(weeks: heatWeeks)
        }
        .onAppear(perform: reload)
    }

    // MARK: - Metric tiles

    private var metricRow: some View {
        HStack(spacing: 10) {
            metricTile(title: "Heute", value: today)
            metricTile(title: "Diese Woche", value: week)
            streakTile
        }
    }

    private func metricTile(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(TimeFormatting.wording(seconds: value))
                .font(.system(.title3, design: .monospaced).weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var streakTile: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Serie")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 3) {
                Image(systemName: "flame")
                    .font(.system(size: 13))
                    .foregroundStyle(streak > 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                Text(streak > 0 ? "\(streak)" : "–")
                    .font(.system(.title3, design: .monospaced).weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 7-day chart (unchanged from v3)

    private var chart: some View {
        let maxSeconds = max(days.map(\.seconds).max() ?? 0, 60)
        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 3) {
                        Rectangle()
                            .fill(index == days.count - 1 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                            .frame(height: max(3, 70 * day.seconds / maxSeconds))
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                        Text(Self.weekdayFormatter.string(from: day.date))
                            .font(.system(size: 9))
                            .foregroundStyle(index == days.count - 1 ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 85, alignment: .bottom)
        }
    }

    // MARK: - Data

    private func reload() {
        today = stats.todaySeconds()
        week = stats.weekSeconds()
        days = stats.last7Days()
        streak = GoalRules.streak(
            endingAt: Date(),
            secondsByDay: { stats.seconds(onDayOf: $0) },
            goalMinutes: preferences.dailyGoalMinutes,
            weekdaysOnly: preferences.streakWeekdaysOnly
        )
        heatWeeks = GoalHeatmapView.build(
            now: Date(),
            goalMinutes: preferences.dailyGoalMinutes,
            secondsByDay: { stats.seconds(onDayOf: $0) }
        )
    }
}
