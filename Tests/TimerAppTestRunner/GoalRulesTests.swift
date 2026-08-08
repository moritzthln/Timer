import Foundation
import TimerCore

private func ts(_ string: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = TimeZone.current
    return formatter.date(from: string)!
}

/// Builds a secondsByDay lookup from "yyyy-MM-dd" keys; missing days are 0.
private func secondsLookup(_ byDay: [String: Double]) -> (Date) -> Double {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone.current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return { byDay[formatter.string(from: $0)] ?? 0 }
}

func runGoalRulesTests() {
    test("goal reached at or above the goal, never with a zero goal") {
        try expect(GoalRules.goalReached(seconds: 10800, goalMinutes: 180), "exactly reached")
        try expect(GoalRules.goalReached(seconds: 10801, goalMinutes: 180), "above")
        try expect(!GoalRules.goalReached(seconds: 10799, goalMinutes: 180), "below")
        try expect(!GoalRules.goalReached(seconds: 10800, goalMinutes: 0), "zero goal never reached")
    }

    test("streak counts consecutive reached days including today") {
        // 2026-08-05 Wed ... 2026-08-07 Fri all reached; Tue empty.
        let lookup = secondsLookup([
            "2026-08-05": 11000, "2026-08-06": 11000, "2026-08-07": 11000,
        ])
        let streak = GoalRules.streak(
            endingAt: ts("2026-08-07 12:00:00"), secondsByDay: lookup,
            goalMinutes: 180, weekdaysOnly: false
        )
        try expectEqual(streak, 3, "three consecutive days")
    }

    test("unreached today starts the count at yesterday") {
        let lookup = secondsLookup(["2026-08-05": 11000, "2026-08-06": 11000])
        let streak = GoalRules.streak(
            endingAt: ts("2026-08-07 09:00:00"), secondsByDay: lookup,
            goalMinutes: 180, weekdaysOnly: false
        )
        try expectEqual(streak, 2, "today pending, streak alive from yesterday")
    }

    test("weekdays-only skips weekends transparently") {
        // Fri 08-07 reached, Sat 08-08 + Sun 08-09 empty, Mon 08-10 reached.
        let lookup = secondsLookup(["2026-08-07": 11000, "2026-08-10": 11000])
        let relaxed = GoalRules.streak(
            endingAt: ts("2026-08-10 20:00:00"), secondsByDay: lookup,
            goalMinutes: 180, weekdaysOnly: true
        )
        try expectEqual(relaxed, 2, "weekend is transparent")
        let strict = GoalRules.streak(
            endingAt: ts("2026-08-10 20:00:00"), secondsByDay: lookup,
            goalMinutes: 180, weekdaysOnly: false
        )
        try expectEqual(strict, 1, "empty Sunday breaks the strict streak")
    }

    test("weekends never extend a weekdays-only streak") {
        // Sat + Sun reached, Fri reached, Thu empty; ending on the Sunday.
        let lookup = secondsLookup([
            "2026-08-07": 11000, "2026-08-08": 11000, "2026-08-09": 11000,
        ])
        let streak = GoalRules.streak(
            endingAt: ts("2026-08-09 12:00:00"), secondsByDay: lookup,
            goalMinutes: 180, weekdaysOnly: true
        )
        try expectEqual(streak, 1, "only Friday counts")
    }

    test("streak walks across the year boundary") {
        // 2026-01-01 is a Thursday, 2025-12-30 empty.
        let lookup = secondsLookup(["2025-12-31": 11000, "2026-01-01": 11000])
        let streak = GoalRules.streak(
            endingAt: ts("2026-01-01 22:00:00"), secondsByDay: lookup,
            goalMinutes: 180, weekdaysOnly: false
        )
        try expectEqual(streak, 2, "Dec 31 + Jan 1")
    }

    test("heat levels map to five intensities relative to the goal") {
        try expectEqual(GoalRules.heatLevel(seconds: 0, goalMinutes: 180), 0, "empty")
        try expectEqual(GoalRules.heatLevel(seconds: 60, goalMinutes: 180), 1, "some")
        try expectEqual(GoalRules.heatLevel(seconds: 5400, goalMinutes: 180), 2, "half")
        try expectEqual(GoalRules.heatLevel(seconds: 10800, goalMinutes: 180), 3, "goal")
        try expectEqual(GoalRules.heatLevel(seconds: 16200, goalMinutes: 180), 4, "150 percent")
    }
}
