import Foundation

public struct DayStat: Equatable {
    public let date: Date
    public let seconds: Double
}

public final class StatsStore {
    private let defaults: UserDefaults
    private let calendar: Calendar
    private static let bucketsKey = "focusStatsBuckets"

    private let dayFormatter: DateFormatter

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var iso = Calendar(identifier: .iso8601) // Monday-start weeks
        iso.timeZone = TimeZone.current
        self.calendar = iso
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        self.dayFormatter = formatter
    }

    private var buckets: [String: Double] {
        get { defaults.dictionary(forKey: Self.bucketsKey) as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: Self.bucketsKey) }
    }

    /// Credits the wall-clock interval, splitting at local midnights.
    public func add(focusFrom start: Date, to end: Date) {
        guard end > start else { return }
        var stored = buckets
        var cursor = start
        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let segmentEnd = min(end, nextMidnight)
            let key = dayFormatter.string(from: cursor)
            stored[key, default: 0] += segmentEnd.timeIntervalSince(cursor)
            cursor = segmentEnd
        }
        buckets = stored
    }

    public func seconds(onDayOf date: Date) -> Double {
        buckets[dayFormatter.string(from: date)] ?? 0
    }

    public func todaySeconds(now: Date = Date()) -> Double {
        seconds(onDayOf: now)
    }

    /// Sum over the current ISO week (Monday...Sunday) containing `now`.
    public func weekSeconds(now: Date = Date()) -> Double {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        var total = 0.0
        var cursor = week.start
        while cursor < week.end {
            total += seconds(onDayOf: cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return total
    }

    /// Seven day stats, oldest first, ending with the day containing `now`.
    public func last7Days(now: Date = Date()) -> [DayStat] {
        (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            return DayStat(date: day, seconds: seconds(onDayOf: day))
        }
    }
}
