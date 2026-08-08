import Foundation

/// One finished focus window and how much of it was spent in distracting apps.
/// Records store computed seconds, not categories — category changes only
/// affect future calculations.
public struct FocusSessionRecord: Codable, Equatable, Identifiable {
    public let id: UUID
    public var start: Date
    public var end: Date
    public var distractedSeconds: Double

    public init(id: UUID = UUID(), start: Date, end: Date, distractedSeconds: Double) {
        self.id = id
        self.start = start
        self.end = end
        self.distractedSeconds = distractedSeconds
    }
}

/// Per-day JSON files `sessions/YYYY-MM-DD.json`; same mechanics as
/// ActivityStore: midnight split on write, corrupt file reads as empty.
public final class SessionStore {
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

    /// Default production location: ~/Library/Application Support/Timer/sessions
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Timer/sessions", isDirectory: true)
    }

    // MARK: - Writing

    /// Appends the record, splitting at local midnights; distracted time is
    /// distributed proportionally to each piece's share of the duration and
    /// clamped into 0...duration up front.
    public func append(_ record: FocusSessionRecord) {
        let duration = record.end.timeIntervalSince(record.start)
        guard duration > 0 else { return }
        let distracted = min(max(0, record.distractedSeconds), duration)
        var cursor = record.start
        while cursor < record.end {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let pieceEnd = min(record.end, nextMidnight)
            let share = pieceEnd.timeIntervalSince(cursor) / duration
            let piece = FocusSessionRecord(
                id: record.id, start: cursor, end: pieceEnd,
                distractedSeconds: distracted * share
            )
            var records = load(day: cursor)
            records.append(piece)
            save(records, day: cursor)
            cursor = pieceEnd
        }
    }

    // MARK: - Reading

    public func records(on day: Date) -> [FocusSessionRecord] {
        load(day: day).sorted { $0.start < $1.start }
    }

    /// Duration-weighted day score 0...1; nil when the day has no records.
    public func dayScore(for date: Date) -> Double? {
        score(of: load(day: date))
    }

    /// Duration-weighted score over the ISO week (Mon–Sun) containing `now`;
    /// nil when the week has no records.
    public func weekScore(now: Date = Date()) -> Double? {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
        var records: [FocusSessionRecord] = []
        var cursor = week.start
        while cursor < week.end {
            records.append(contentsOf: load(day: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return score(of: records)
    }

    private func score(of records: [FocusSessionRecord]) -> Double? {
        let duration = records.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        guard duration > 0 else { return nil }
        let distracted = records.reduce(0.0) { $0 + $1.distractedSeconds }
        return min(1, max(0, 1 - distracted / duration))
    }

    // MARK: - Files

    private func fileURL(day: Date) -> URL {
        directory.appendingPathComponent(dayFormatter.string(from: day) + ".json")
    }

    private func load(day: Date) -> [FocusSessionRecord] {
        guard let data = try? Data(contentsOf: fileURL(day: day)),
              let records = try? JSONDecoder().decode([FocusSessionRecord].self, from: data) else {
            return []
        }
        return records
    }

    private func save(_ records: [FocusSessionRecord], day: Date) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL(day: day), options: .atomic)
    }
}
