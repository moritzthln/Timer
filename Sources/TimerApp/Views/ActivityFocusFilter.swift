import Foundation
import TimerCore

/// v12: the data side of the "Nur Fokus-Zeit" filter — sums the pure
/// `FocusClip` overlap over the already-cached day summaries and their focus
/// intervals (no extra store or log reads). Rows with zero clipped time
/// disappear; the rest sorts by clipped totals.
enum ActivityFocusFilter {
    /// Sum of the intervals themselves — the "Fokus-Zeit · …" header value.
    static func focusSeconds(_ intervals: [FocusInterval]) -> Double {
        intervals.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    /// Clipped app rows of one day.
    static func apps(_ summary: DaySummary, intervals: [FocusInterval]) -> [AppUsage] {
        appRows(appTotals(days: [(summary, intervals)]))
    }

    /// Clipped app rows of a week: the seven days' intersections, summed.
    static func apps(_ days: [WeekDay]) -> [AppUsage] {
        appRows(appTotals(days: days.map { ($0.summary, $0.focus) }))
    }

    /// Clipped domain rows of one day, per browser.
    static func sites(_ summary: DaySummary, intervals: [FocusInterval]) -> [String: [SiteUsage]] {
        siteRows(siteTotals(days: [(summary, intervals)]))
    }

    /// Clipped domain rows of a week, per browser.
    static func sites(_ days: [WeekDay]) -> [String: [SiteUsage]] {
        siteRows(siteTotals(days: days.map { ($0.summary, $0.focus) }))
    }

    /// Sparkline data while the filter is on: per-app clipped seconds per
    /// day, keyed by bundle id (same shape as `ActivitySparklineView.series`).
    static func sparkSeries(
        summaries: [DaySummary], focus: [[FocusInterval]]
    ) -> [String: [Double]] {
        var result: [String: [Double]] = [:]
        for (index, summary) in summaries.enumerated() {
            let intervals = index < focus.count ? focus[index] : []
            for app in summary.apps {
                var values = result[app.bundleID] ?? Array(repeating: 0, count: summaries.count)
                values[index] = clippedTotal(app.segments, intervals)
                result[app.bundleID] = values
            }
        }
        return result
    }

    // MARK: - Shared summation

    private static func clippedTotal(
        _ segments: [ActivitySegment], _ intervals: [FocusInterval]
    ) -> Double {
        segments.reduce(0) {
            $0 + FocusClip.clippedSeconds(
                segmentStart: $1.start, segmentEnd: $1.end, intervals: intervals
            )
        }
    }

    private static func appTotals(
        days: [(DaySummary, [FocusInterval])]
    ) -> [String: (name: String, seconds: Double)] {
        var result: [String: (name: String, seconds: Double)] = [:]
        for (summary, intervals) in days {
            for app in summary.apps {
                let clipped = clippedTotal(app.segments, intervals)
                guard clipped > 0 else { continue }
                var entry = result[app.bundleID] ?? (app.name, 0)
                entry.seconds += clipped
                result[app.bundleID] = entry
            }
        }
        return result
    }

    private static func appRows(
        _ totals: [String: (name: String, seconds: Double)]
    ) -> [AppUsage] {
        totals.map { bundleID, entry in
            AppUsage(
                bundleID: bundleID, name: entry.name,
                totalSeconds: entry.seconds, segments: []
            )
        }.sorted {
            $0.totalSeconds != $1.totalSeconds
                ? $0.totalSeconds > $1.totalSeconds : $0.bundleID < $1.bundleID
        }
    }

    private static func siteTotals(
        days: [(DaySummary, [FocusInterval])]
    ) -> [String: [String: Double]] {
        var result: [String: [String: Double]] = [:]
        for (summary, intervals) in days {
            for segment in summary.siteSegments {
                guard case .site(let domain, let browser) = segment.kind else { continue }
                let clipped = FocusClip.clippedSeconds(
                    segmentStart: segment.start, segmentEnd: segment.end, intervals: intervals
                )
                guard clipped > 0 else { continue }
                result[browser, default: [:]][domain, default: 0] += clipped
            }
        }
        return result
    }

    private static func siteRows(
        _ totals: [String: [String: Double]]
    ) -> [String: [SiteUsage]] {
        totals.mapValues { domains in
            domains.map { SiteUsage(domain: $0.key, totalSeconds: $0.value) }
                .sorted {
                    $0.totalSeconds != $1.totalSeconds
                        ? $0.totalSeconds > $1.totalSeconds : $0.domain < $1.domain
                }
        }
    }
}
