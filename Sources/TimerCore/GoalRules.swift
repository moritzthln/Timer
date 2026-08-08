import Foundation

/// Pure daily-goal logic: reached check, streak counting, heatmap levels.
public enum GoalRules {
    /// ISO-8601 (Monday-start) calendar in the local time zone.
    public static func localISOCalendar() -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone.current
        return calendar
    }

    public static func goalReached(seconds: Double, goalMinutes: Int) -> Bool {
        goalMinutes > 0 && seconds >= Double(goalMinutes) * 60
    }

    /// Consecutive goal-reached days ending at `endingAt`'s day, walking
    /// backwards. The current day extends the streak when reached and is
    /// skipped when not (it may still fill up); any earlier miss stops the
    /// count. With `weekdaysOnly`, weekend days are transparent: they never
    /// count and never break. The walk is capped at ten years.
    public static func streak(
        endingAt now: Date,
        secondsByDay: (Date) -> Double,
        goalMinutes: Int,
        weekdaysOnly: Bool,
        calendar: Calendar = GoalRules.localISOCalendar()
    ) -> Int {
        let today = calendar.startOfDay(for: now)
        var day = today
        var count = 0
        for _ in 0..<3660 {
            let transparent = weekdaysOnly && calendar.isDateInWeekend(day)
            if !transparent {
                if goalReached(seconds: secondsByDay(day), goalMinutes: goalMinutes) {
                    count += 1
                } else if day != today {
                    break
                }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// Heatmap intensity 0–4: nothing · >0 · ≥50 % · ≥100 % · ≥150 % of goal.
    public static func heatLevel(seconds: Double, goalMinutes: Int) -> Int {
        guard seconds > 0 else { return 0 }
        let goal = Double(max(1, goalMinutes)) * 60
        if seconds >= goal * 1.5 { return 4 }
        if seconds >= goal { return 3 }
        if seconds >= goal * 0.5 { return 2 }
        return 1
    }
}
