import Foundation
import TimerCore

private func freshStats() -> StatsStore {
    let suite = "StatsStoreTests"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return StatsStore(defaults: defaults)
}

private func date(_ string: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = TimeZone.current
    return formatter.date(from: string)!
}

func runStatsStoreTests() {
    test("adding a segment credits its day") {
        let stats = freshStats()
        stats.add(focusFrom: date("2026-08-07 10:00:00"), to: date("2026-08-07 10:25:00"))
        try expectEqual(stats.seconds(onDayOf: date("2026-08-07 12:00:00")), 1500, accuracy: 0.5, "25 min")
    }

    test("segments accumulate on the same day") {
        let stats = freshStats()
        stats.add(focusFrom: date("2026-08-07 10:00:00"), to: date("2026-08-07 10:10:00"))
        stats.add(focusFrom: date("2026-08-07 14:00:00"), to: date("2026-08-07 14:05:00"))
        try expectEqual(stats.seconds(onDayOf: date("2026-08-07 12:00:00")), 900, accuracy: 0.5, "10+5 min")
    }

    test("midnight-crossing segment splits across days") {
        let stats = freshStats()
        stats.add(focusFrom: date("2026-08-06 23:50:00"), to: date("2026-08-07 00:20:00"))
        try expectEqual(stats.seconds(onDayOf: date("2026-08-06 12:00:00")), 600, accuracy: 0.5, "10 min before midnight")
        try expectEqual(stats.seconds(onDayOf: date("2026-08-07 12:00:00")), 1200, accuracy: 0.5, "20 min after midnight")
    }

    test("invalid segment (end before start) is ignored") {
        let stats = freshStats()
        stats.add(focusFrom: date("2026-08-07 10:00:00"), to: date("2026-08-07 09:00:00"))
        try expectEqual(stats.seconds(onDayOf: date("2026-08-07 12:00:00")), 0, accuracy: 0.5, "ignored")
    }

    test("week sums the ISO week Monday through Sunday") {
        let stats = freshStats()
        // 2026-08-07 is a Friday; its ISO week runs Mon 2026-08-03 ... Sun 2026-08-09.
        stats.add(focusFrom: date("2026-08-03 09:00:00"), to: date("2026-08-03 09:30:00"))
        stats.add(focusFrom: date("2026-08-07 09:00:00"), to: date("2026-08-07 09:30:00"))
        stats.add(focusFrom: date("2026-08-02 09:00:00"), to: date("2026-08-02 09:30:00")) // Sunday before → previous week
        try expectEqual(stats.weekSeconds(now: date("2026-08-07 12:00:00")), 3600, accuracy: 0.5, "Mon+Fri only")
    }

    test("last7Days returns seven entries ending today") {
        let stats = freshStats()
        stats.add(focusFrom: date("2026-08-07 09:00:00"), to: date("2026-08-07 09:30:00"))
        stats.add(focusFrom: date("2026-08-01 09:00:00"), to: date("2026-08-01 09:30:00")) // 6 days before
        let days = stats.last7Days(now: date("2026-08-07 12:00:00"))
        try expectEqual(days.count, 7, "seven entries")
        try expectEqual(days[0].seconds, 1800, accuracy: 0.5, "oldest is 2026-08-01")
        try expectEqual(days[6].seconds, 1800, accuracy: 0.5, "today last")
        try expectEqual(days[3].seconds, 0, accuracy: 0.5, "empty day is zero")
    }
}
