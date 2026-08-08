import SwiftUI
import TimerCore

/// GitHub-style goal heatmap: last 12 months, columns = ISO weeks
/// (Monday-start), rows = Mon–Sun, five intensity levels vs. the daily goal.
/// Today is outlined; future days of the current week stay blank. No
/// tooltips (v5). 53 columns × 4 pt cells + 1.5 pt gaps = 290 pt, inside
/// the 340 pt window (308 pt content width).
struct GoalHeatmapView: View {
    struct Day: Identifiable {
        let id: Int
        let date: Date
        let level: Int // 0...4
        let isToday: Bool
        let isFuture: Bool
    }

    let weeks: [[Day]]

    private static let cellSize: CGFloat = 4
    private static let spacing: CGFloat = 1.5

    var body: some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: Self.spacing) {
                    ForEach(week) { day in
                        cell(day)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(_ day: Day) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(day.isFuture ? Color.clear : Self.levelColors[day.level])
            .frame(width: Self.cellSize, height: Self.cellSize)
            .overlay {
                RoundedRectangle(cornerRadius: 1)
                    .strokeBorder(day.isToday ? Color.primary : Color.clear, lineWidth: 0.5)
            }
    }

    private static let levelColors: [Color] = [
        Color.primary.opacity(0.08),
        Color.accentColor.opacity(0.25),
        Color.accentColor.opacity(0.5),
        Color.accentColor.opacity(0.75),
        Color.accentColor,
    ]

    /// 53 week columns: the ISO week containing `now` plus the 52 before it.
    /// Days before install simply look up 0 seconds → level 0 (no data ≠ failure).
    static func build(
        now: Date, goalMinutes: Int, secondsByDay: (Date) -> Double
    ) -> [[Day]] {
        let calendar = GoalRules.localISOCalendar()
        let today = calendar.startOfDay(for: now)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
              let firstMonday = calendar.date(byAdding: .weekOfYear, value: -52, to: thisWeek.start) else {
            return []
        }
        var weeks: [[Day]] = []
        var id = 0
        for week in 0...52 {
            var column: [Day] = []
            for dayIndex in 0..<7 {
                guard let date = calendar.date(
                    byAdding: .day, value: week * 7 + dayIndex, to: firstMonday
                ) else { continue }
                let day = calendar.startOfDay(for: date)
                let isFuture = day > today
                column.append(Day(
                    id: id,
                    date: day,
                    level: isFuture ? 0 : GoalRules.heatLevel(
                        seconds: secondsByDay(day), goalMinutes: goalMinutes
                    ),
                    isToday: day == today,
                    isFuture: isFuture
                ))
                id += 1
            }
            weeks.append(column)
        }
        return weeks
    }
}
