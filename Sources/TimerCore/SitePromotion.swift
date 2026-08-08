import Foundation

/// v13: display-time aggregation behind promoted website rows — configured
/// domains (e.g. instagram.com, youtube.com) leave their browsers' disclosure
/// lists and become first-class rows in the activity app list. Pure math over
/// already-aggregated usage; stored data never changes, so history follows
/// the current list automatically.
public enum SitePromotion {
    /// Pseudo bundle-id namespace of promoted rows — stable for selection
    /// guards and palette ranking, and collision-free with real bundle ids
    /// (":" never appears in those).
    public static let idPrefix = "site:"

    public static func rowID(forDomain domain: String) -> String {
        idPrefix + domain
    }

    public static func isPromotedRowID(_ id: String) -> Bool {
        id.hasPrefix(idPrefix)
    }

    /// Merges promoted domains out of the per-browser site lists: each
    /// promoted entry with time becomes one synthesized row (cross-browser
    /// sum, suffix matching via `FocusBlockRules.domainMatches`, first entry
    /// in `promoted` order wins so overlapping entries never double-count).
    /// Browser rows shrink by the seconds attributed away (clamped at 0) and
    /// their disclosure lists lose the promoted domains; lists that empty out
    /// drop entirely. Rows re-sort by seconds (ties by id, stable colors).
    public static func apply(
        apps: [AppUsage],
        sitesByBrowser: [String: [SiteUsage]],
        promoted: [String]
    ) -> (rows: [AppUsage], sitesByBrowser: [String: [SiteUsage]]) {
        guard !promoted.isEmpty else { return (apps, sitesByBrowser) }

        var promotedTotals: [String: Double] = [:]
        var reductions: [String: Double] = [:]
        var cleansed: [String: [SiteUsage]] = [:]
        for (browser, sites) in sitesByBrowser {
            var remaining: [SiteUsage] = []
            for site in sites {
                if let entry = firstMatch(host: site.domain, promoted: promoted) {
                    promotedTotals[entry, default: 0] += site.totalSeconds
                    reductions[browser, default: 0] += site.totalSeconds
                } else {
                    remaining.append(site)
                }
            }
            if !remaining.isEmpty { cleansed[browser] = remaining }
        }

        var rows = apps.map { app in
            reductions[app.bundleID].map {
                AppUsage(
                    bundleID: app.bundleID, name: app.name,
                    totalSeconds: max(0, app.totalSeconds - $0),
                    segments: app.segments
                )
            } ?? app
        }
        for entry in promoted {
            guard let seconds = promotedTotals.removeValue(forKey: entry),
                  seconds > 0 else { continue }
            rows.append(AppUsage(
                bundleID: rowID(forDomain: entry), name: entry,
                totalSeconds: seconds, segments: []
            ))
        }
        rows.sort {
            $0.totalSeconds != $1.totalSeconds
                ? $0.totalSeconds > $1.totalSeconds : $0.bundleID < $1.bundleID
        }
        return (rows, cleansed)
    }

    /// Palette ranks over the promoted rows: `apply`'s sorted output fed
    /// through the shared `WeekRanking` ordering (0 = most used). Views pass
    /// their raw (unfiltered) aggregates so colors stay stable while the
    /// focus filter toggles — the v12 behavior, now promotion-aware.
    public static func ranks(
        apps: [AppUsage],
        sitesByBrowser: [String: [SiteUsage]],
        promoted: [String]
    ) -> [String: Int] {
        let rows = apply(apps: apps, sitesByBrowser: sitesByBrowser, promoted: promoted).rows
        return WeekRanking.rank(appTotals: Dictionary(
            uniqueKeysWithValues: rows.map { ($0.bundleID, $0.totalSeconds) }
        ))
    }

    /// One day's promoted seconds per entry and attributed seconds per
    /// browser, from the day's raw site segments — the data behind promoted
    /// sparkline bars. A clip limits every segment to its overlap with the
    /// day's focus intervals (the "Nur Fokus-Zeit" filter); nil counts full
    /// durations.
    public static func dayTotals(
        siteSegments: [ActivitySegment],
        promoted: [String],
        clippedTo clip: [FocusInterval]?
    ) -> (promotedSeconds: [String: Double], browserReductions: [String: Double]) {
        var promotedSeconds: [String: Double] = [:]
        var reductions: [String: Double] = [:]
        guard !promoted.isEmpty else { return (promotedSeconds, reductions) }
        for segment in siteSegments {
            guard case .site(let domain, let browser) = segment.kind,
                  let entry = firstMatch(host: domain, promoted: promoted) else { continue }
            let seconds = clip.map {
                FocusClip.clippedSeconds(
                    segmentStart: segment.start, segmentEnd: segment.end, intervals: $0
                )
            } ?? segment.end.timeIntervalSince(segment.start)
            guard seconds > 0 else { continue }
            promotedSeconds[entry, default: 0] += seconds
            reductions[browser, default: 0] += seconds
        }
        return (promotedSeconds, reductions)
    }

    /// Sparkline overlay: takes the base per-app daily series plus each
    /// window day's site segments (and optional focus clip), adds one series
    /// per promoted row and shrinks the browsers' bars by the seconds
    /// attributed away (clamped at 0) — so list totals and sparklines tell
    /// the same story.
    public static func sparkSeries(
        base: [String: [Double]],
        days: [(siteSegments: [ActivitySegment], clip: [FocusInterval]?)],
        promoted: [String]
    ) -> [String: [Double]] {
        guard !promoted.isEmpty else { return base }
        var result = base
        for (index, day) in days.enumerated() {
            let totals = dayTotals(
                siteSegments: day.siteSegments, promoted: promoted, clippedTo: day.clip
            )
            for (entry, seconds) in totals.promotedSeconds {
                let id = rowID(forDomain: entry)
                var values = result[id] ?? Array(repeating: 0, count: days.count)
                if index < values.count { values[index] = seconds }
                result[id] = values
            }
            for (browser, reduction) in totals.browserReductions {
                guard var values = result[browser], index < values.count else { continue }
                values[index] = max(0, values[index] - reduction)
                result[browser] = values
            }
        }
        return result
    }

    /// First promoted entry (in list order) that `host` equals or is a
    /// subdomain of — the blocker's suffix semantics.
    static func firstMatch(host: String, promoted: [String]) -> String? {
        promoted.first { FocusBlockRules.domainMatches(host: host, entry: $0) }
    }
}
