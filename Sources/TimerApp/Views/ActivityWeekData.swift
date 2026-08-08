import Foundation
import TimerCore

/// One day of the displayed week, paired with its cached summary and the
/// day's focus intervals (v10 traces).
struct WeekDay: Identifiable {
    let date: Date
    let summary: DaySummary
    let focus: [FocusInterval]

    var id: Date { date }
}

/// v10: everything the week view renders, assembled from seven cached
/// `daySummary` calls — loaded once per week navigation and kept in view
/// state. Pure aggregation, no extra store reads.
struct WeekData {
    let days: [WeekDay]                        // Mon ... Sun of the ISO week
    let apps: [AppUsage]                       // week totals, sorted desc
    let sitesByBrowser: [String: [SiteUsage]]  // week-aggregated domains
    let presenceSeconds: Double
    let ranks: [String: Int]                   // WeekRanking over week totals

    var hasActivity: Bool {
        days.contains { $0.summary.firstActivity != nil }
    }

    /// ISO week math (Monday-start), local time zone.
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone.current
        return cal
    }()

    static func load(store: ActivityStore, focusLog: FocusLog, weekOf anchor: Date,
                     liveFocusStart: Date? = nil) -> WeekData {
        let start = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start
            ?? calendar.startOfDay(for: anchor)
        let days = (0..<7)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            .map {
                WeekDay(
                    date: $0, summary: store.daySummary(for: $0),
                    focus: LiveFocus.augment(
                        focusLog.intervals(onDay: $0), onDay: $0, liveStart: liveFocusStart
                    )
                )
            }
        return aggregate(days: days)
    }

    private static func aggregate(days: [WeekDay]) -> WeekData {
        var totals: [String: Double] = [:]
        var names: [String: String] = [:]
        var siteTotals: [String: [String: Double]] = [:]
        var presence = 0.0
        for day in days {
            presence += day.summary.presenceSeconds
            for app in day.summary.apps {
                totals[app.bundleID, default: 0] += app.totalSeconds
                names[app.bundleID] = app.name
            }
            for (browser, sites) in day.summary.sitesByBrowser {
                for site in sites {
                    siteTotals[browser, default: [:]][site.domain, default: 0] += site.totalSeconds
                }
            }
        }
        let apps = totals.map { bundleID, total in
            AppUsage(
                bundleID: bundleID, name: names[bundleID] ?? bundleID,
                totalSeconds: total, segments: []
            )
        }.sorted {
            $0.totalSeconds != $1.totalSeconds
                ? $0.totalSeconds > $1.totalSeconds : $0.bundleID < $1.bundleID
        }
        let sites = siteTotals.mapValues { domains in
            domains.map { SiteUsage(domain: $0.key, totalSeconds: $0.value) }
                .sorted { $0.totalSeconds > $1.totalSeconds }
        }
        return WeekData(
            days: days, apps: apps, sitesByBrowser: sites,
            presenceSeconds: presence,
            ranks: WeekRanking.rank(appTotals: totals)
        )
    }
}
