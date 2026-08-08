import Foundation

public struct AppUsage: Equatable {
    public let bundleID: String
    public let name: String
    public let totalSeconds: Double
    public let segments: [ActivitySegment]
}

public struct SiteUsage: Equatable {
    public let domain: String
    public let totalSeconds: Double
}

public struct DaySummary: Equatable {
    public let firstActivity: Date?
    public let lastActivity: Date?
    public let presenceSeconds: Double
    public let presenceSegments: [ActivitySegment]
    public let apps: [AppUsage]                    // sorted by total desc
    public let sitesByBrowser: [String: [SiteUsage]] // sorted by total desc
}

public final class ActivityStore {
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

    /// Default production location: ~/Library/Application Support/Timer/activity
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Timer/activity", isDirectory: true)
    }

    // MARK: - Writing

    public func append(_ segment: ActivitySegment) {
        write(segment, replacingByID: false)
    }

    /// Insert-or-replace by segment id (heartbeat re-persists open segments).
    public func upsert(_ segment: ActivitySegment) {
        write(segment, replacingByID: true)
    }

    private func write(_ segment: ActivitySegment, replacingByID: Bool) {
        guard segment.end > segment.start else { return }
        for piece in splitAtMidnights(segment) {
            var segments = load(day: piece.start)
            if replacingByID {
                segments.removeAll { $0.id == piece.id }
            }
            segments.append(piece)
            save(segments, day: piece.start)
        }
    }

    /// Splits at local midnights; pieces keep the original id (upsert per day file).
    private func splitAtMidnights(_ segment: ActivitySegment) -> [ActivitySegment] {
        var result: [ActivitySegment] = []
        var cursor = segment.start
        while cursor < segment.end {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let pieceEnd = min(segment.end, nextMidnight)
            result.append(ActivitySegment(id: segment.id, kind: segment.kind, start: cursor, end: pieceEnd))
            cursor = pieceEnd
        }
        return result
    }

    // MARK: - Files

    private func fileURL(day: Date) -> URL {
        directory.appendingPathComponent(dayFormatter.string(from: day) + ".json")
    }

    private func load(day: Date) -> [ActivitySegment] {
        guard let data = try? Data(contentsOf: fileURL(day: day)),
              let segments = try? JSONDecoder().decode([ActivitySegment].self, from: data) else {
            return []
        }
        return segments
    }

    private func save(_ segments: [ActivitySegment], day: Date) {
        guard let data = try? JSONEncoder().encode(segments) else { return }
        try? data.write(to: fileURL(day: day), options: .atomic)
    }

    // MARK: - Summary

    public func daySummary(for date: Date) -> DaySummary {
        let segments = load(day: date)

        let presence = segments.filter {
            if case .presence = $0.kind { return true }
            return false
        }.sorted { $0.start < $1.start }
        let presenceSeconds = presence.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }

        var appTotals: [String: (name: String, total: Double, segments: [ActivitySegment])] = [:]
        var siteTotals: [String: [String: Double]] = [:]
        for segment in segments {
            let duration = segment.end.timeIntervalSince(segment.start)
            switch segment.kind {
            case .presence:
                break
            case .app(let bundleID, let name):
                var entry = appTotals[bundleID] ?? (name: name, total: 0, segments: [])
                entry.total += duration
                entry.segments.append(segment)
                appTotals[bundleID] = entry
            case .site(let domain, let browser):
                siteTotals[browser, default: [:]][domain, default: 0] += duration
            }
        }

        let apps = appTotals.map { bundleID, entry in
            AppUsage(
                bundleID: bundleID, name: entry.name, totalSeconds: entry.total,
                segments: entry.segments.sorted { $0.start < $1.start }
            )
        }.sorted { $0.totalSeconds > $1.totalSeconds }

        let sites = siteTotals.mapValues { domains in
            domains.map { SiteUsage(domain: $0.key, totalSeconds: $0.value) }
                .sorted { $0.totalSeconds > $1.totalSeconds }
        }

        return DaySummary(
            firstActivity: presence.first?.start,
            lastActivity: presence.last?.end,
            presenceSeconds: presenceSeconds,
            presenceSegments: presence,
            apps: apps,
            sitesByBrowser: sites
        )
    }
}
