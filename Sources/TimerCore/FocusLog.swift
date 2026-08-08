import Foundation

public struct FocusInterval: Codable, Equatable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// v10: append-only log of finished focus intervals (timer runs and pomodoro
/// focus phases), one JSON file per local day — the data behind the focus
/// traces in the activity timelines. Same file pattern as ActivityStore.
public final class FocusLog {
    private let directory: URL
    private let calendar: Calendar
    private let dayFormatter: DateFormatter

    public init(directory: URL) {
        self.directory = directory
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone.current
        self.calendar = cal
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        self.dayFormatter = formatter
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Default production location: ~/Library/Application Support/Timer/focus
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Timer/focus", isDirectory: true)
    }

    /// Records a finished focus interval, split at local midnights.
    /// Intervals with `end <= start` are discarded.
    public func append(start: Date, end: Date) {
        guard end > start else { return }
        var cursor = start
        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let pieceEnd = min(end, nextMidnight)
            var intervals = load(day: cursor)
            intervals.append(FocusInterval(start: cursor, end: pieceEnd))
            save(intervals, day: cursor)
            cursor = pieceEnd
        }
    }

    /// All intervals recorded on the local day of `date`, sorted by start.
    /// Missing or corrupt files read as empty.
    public func intervals(onDay date: Date) -> [FocusInterval] {
        load(day: date).sorted { $0.start < $1.start }
    }

    // MARK: - Files

    private func fileURL(day: Date) -> URL {
        directory.appendingPathComponent(dayFormatter.string(from: day) + ".json")
    }

    private func load(day: Date) -> [FocusInterval] {
        guard let data = try? Data(contentsOf: fileURL(day: day)),
              let intervals = try? JSONDecoder().decode([FocusInterval].self, from: data) else {
            return []
        }
        return intervals
    }

    private func save(_ intervals: [FocusInterval], day: Date) {
        guard let data = try? JSONEncoder().encode(intervals) else { return }
        try? data.write(to: fileURL(day: day), options: .atomic)
    }
}
