import SwiftUI
import TimerCore

/// GitHub-style focus heatmap: last 12 months, columns = ISO weeks
/// (Monday-start), rows = Mon–Sun, five intensity levels relative to the
/// busiest day of the visible period (`HeatmapScale`, absolute — v8 removed
/// the daily goal). Today is outlined; future days of the current week stay
/// blank. v8: cells derive their size from the available width (width ÷ 53
/// columns) and month labels run along the top, both scaling with the
/// resizable stats window.
struct HeatmapView: View {
    struct Day: Identifiable {
        let id: Int
        let date: Date
        let level: Int // 0...4
        let isToday: Bool
        let isFuture: Bool
    }

    let weeks: [[Day]]
    let width: CGFloat

    private static let spacing: CGFloat = 1.5

    private var cellSize: CGFloat {
        let columns = CGFloat(max(1, weeks.count))
        return max(3, (width - (columns - 1) * Self.spacing) / columns)
    }

    private var labelFontSize: CGFloat {
        min(11, max(8, cellSize + 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            monthLabelRow
            grid
        }
    }

    // MARK: - Month labels

    /// One label per month boundary (column whose Monday starts a new
    /// month); boundaries closer than three columns to the previous label
    /// are skipped so labels never overlap.
    private var monthLabels: [(index: Int, text: String)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let calendar = Calendar.current
        var labels: [(Int, String)] = []
        var lastMonth = -1
        var lastLabelIndex = -3
        for (index, week) in weeks.enumerated() {
            guard let monday = week.first?.date else { continue }
            let month = calendar.component(.month, from: monday)
            guard month != lastMonth else { continue }
            lastMonth = month
            guard index - lastLabelIndex >= 3 else { continue }
            labels.append((index, formatter.string(from: monday)))
            lastLabelIndex = index
        }
        return labels
    }

    private var monthLabelRow: some View {
        ZStack(alignment: .topLeading) {
            ForEach(monthLabels, id: \.index) { label in
                Text(label.text)
                    .font(.system(size: labelFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(x: CGFloat(label.index) * (cellSize + Self.spacing))
            }
        }
        .frame(maxWidth: .infinity, minHeight: labelFontSize + 3, alignment: .topLeading)
    }

    // MARK: - Grid

    private var grid: some View {
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
        let radius = min(2, max(1, cellSize / 4))
        return RoundedRectangle(cornerRadius: radius)
            .fill(day.isFuture ? Color.clear : Self.levelColors[day.level])
            .frame(width: cellSize, height: cellSize)
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(
                        day.isToday ? Color.primary : Color.clear,
                        lineWidth: max(0.5, cellSize / 10)
                    )
            }
    }

    private static let levelColors: [Color] = [
        Color.primary.opacity(0.08),
        Color.accentColor.opacity(0.25),
        Color.accentColor.opacity(0.5),
        Color.accentColor.opacity(0.75),
        Color.accentColor,
    ]

    // MARK: - Data

    /// ISO-8601 (Monday-start) calendar in the local time zone.
    private static func localISOCalendar() -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone.current
        return calendar
    }

    /// 53 week columns: the ISO week containing `now` plus the 52 before it.
    /// First pass gathers every day's seconds to find the period maximum,
    /// second pass maps each day to its `HeatmapScale` level. Days before
    /// install simply look up 0 seconds → level 0 (no data ≠ failure).
    static func build(now: Date, secondsByDay: (Date) -> Double) -> [[Day]] {
        let calendar = localISOCalendar()
        let today = calendar.startOfDay(for: now)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
              let firstMonday = calendar.date(byAdding: .weekOfYear, value: -52, to: thisWeek.start) else {
            return []
        }
        var days: [(date: Date, seconds: Double, isFuture: Bool)] = []
        for offset in 0..<(53 * 7) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstMonday) else { continue }
            let day = calendar.startOfDay(for: date)
            let isFuture = day > today
            days.append((day, isFuture ? 0 : secondsByDay(day), isFuture))
        }
        let maxSeconds = days.map(\.seconds).max() ?? 0
        var weeks: [[Day]] = []
        for (index, day) in days.enumerated() {
            if index % 7 == 0 { weeks.append([]) }
            weeks[weeks.count - 1].append(Day(
                id: index,
                date: day.date,
                level: HeatmapScale.level(seconds: day.seconds, maxSeconds: maxSeconds),
                isToday: day.date == today,
                isFuture: day.isFuture
            ))
        }
        return weeks
    }
}
