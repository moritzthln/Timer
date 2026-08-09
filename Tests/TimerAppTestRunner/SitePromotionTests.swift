import Foundation
import TimerCore

private func app(_ id: String, _ seconds: Double, name: String? = nil) -> AppUsage {
    AppUsage(bundleID: id, name: name ?? id, totalSeconds: seconds, segments: [])
}

func runSitePromotionTests() {
    let safari = "com.apple.Safari"
    let chrome = "com.google.Chrome"

    test("empty promoted list passes apps and sites through unchanged") {
        let apps = [app(safari, 300), app("com.apple.dt.Xcode", 200)]
        let sites = [safari: [SiteUsage(domain: "youtube.com", totalSeconds: 120)]]
        let result = SitePromotion.apply(apps: apps, sitesByBrowser: sites, promoted: [])
        try expectEqual(result.rows, apps, "rows untouched")
        try expectEqual(result.sitesByBrowser, sites, "disclosure untouched")
    }

    test("promoted domain in one browser becomes its own row, browser reduced") {
        let apps = [app(safari, 300), app("com.apple.dt.Xcode", 200)]
        let sites = [safari: [
            SiteUsage(domain: "youtube.com", totalSeconds: 120),
            SiteUsage(domain: "apple.com", totalSeconds: 60),
        ]]
        let result = SitePromotion.apply(
            apps: apps, sitesByBrowser: sites, promoted: ["youtube.com"]
        )
        try expectEqual(result.rows, [
            app("com.apple.dt.Xcode", 200),
            app(safari, 180),
            app("site:youtube.com", 120, name: "youtube.com"),
        ], "row synthesized, browser reduced by attributed seconds, sorted by seconds")
        try expectEqual(
            result.sitesByBrowser,
            [safari: [SiteUsage(domain: "apple.com", totalSeconds: 60)]],
            "promoted domain removed from the disclosure list"
        )
    }

    test("promoted seconds merge across browsers into one row") {
        let apps = [app(safari, 300), app(chrome, 250)]
        let sites = [
            safari: [SiteUsage(domain: "youtube.com", totalSeconds: 100)],
            chrome: [SiteUsage(domain: "youtube.com", totalSeconds: 50)],
        ]
        let result = SitePromotion.apply(
            apps: apps, sitesByBrowser: sites, promoted: ["youtube.com"]
        )
        try expectEqual(result.rows, [
            app(safari, 200),
            app(chrome, 200),
            app("site:youtube.com", 150, name: "youtube.com"),
        ], "one merged row, each browser reduced by its own share")
        try expectEqual(result.sitesByBrowser, [:], "fully promoted lists drop out")
    }

    test("subdomains aggregate onto the promoted entry") {
        let apps = [app(safari, 400)]
        let sites = [safari: [
            SiteUsage(domain: "m.youtube.com", totalSeconds: 90),
            SiteUsage(domain: "youtube.com", totalSeconds: 60),
            SiteUsage(domain: "notyoutube.com", totalSeconds: 30),
        ]]
        let result = SitePromotion.apply(
            apps: apps, sitesByBrowser: sites, promoted: ["youtube.com"]
        )
        try expectEqual(result.rows, [
            app(safari, 250),
            app("site:youtube.com", 150, name: "youtube.com"),
        ], "suffix matches merge; lookalike domain stays")
        try expectEqual(
            result.sitesByBrowser,
            [safari: [SiteUsage(domain: "notyoutube.com", totalSeconds: 30)]],
            "only genuine matches leave the disclosure list"
        )
    }

    test("overlapping promoted entries: first match in list order wins") {
        let apps = [app(safari, 400)]
        let sites = [safari: [SiteUsage(domain: "m.youtube.com", totalSeconds: 90)]]
        let broadFirst = SitePromotion.apply(
            apps: apps, sitesByBrowser: sites, promoted: ["youtube.com", "m.youtube.com"]
        )
        try expectEqual(broadFirst.rows, [
            app(safari, 310),
            app("site:youtube.com", 90, name: "youtube.com"),
        ], "broad entry first captures the segment, no second row")
        let specificFirst = SitePromotion.apply(
            apps: apps, sitesByBrowser: sites, promoted: ["m.youtube.com", "youtube.com"]
        )
        try expectEqual(specificFirst.rows, [
            app(safari, 310),
            app("site:m.youtube.com", 90, name: "m.youtube.com"),
        ], "specific entry first takes priority, still exactly one row")
    }

    test("browser total never drops below zero") {
        let apps = [app(safari, 50)]
        let sites = [safari: [SiteUsage(domain: "youtube.com", totalSeconds: 80)]]
        let result = SitePromotion.apply(
            apps: apps, sitesByBrowser: sites, promoted: ["youtube.com"]
        )
        try expectEqual(result.rows, [
            app("site:youtube.com", 80, name: "youtube.com"),
            app(safari, 0),
        ], "reduction clamps at 0")
    }

    test("promoted domain without any time gets no row") {
        let apps = [app(safari, 300)]
        let sites = [safari: [SiteUsage(domain: "apple.com", totalSeconds: 60)]]
        let result = SitePromotion.apply(
            apps: apps, sitesByBrowser: sites, promoted: ["instagram.com"]
        )
        try expectEqual(result.rows, [app(safari, 300)], "no zero-time rows")
        try expectEqual(result.sitesByBrowser, sites, "disclosure keeps unrelated domains")
    }

    test("ranks index the promoted row order for the palette") {
        let apps = [app(safari, 300), app("com.apple.dt.Xcode", 200)]
        let sites = [safari: [SiteUsage(domain: "youtube.com", totalSeconds: 120)]]
        let ranks = SitePromotion.ranks(
            apps: apps, sitesByBrowser: sites, promoted: ["youtube.com"]
        )
        try expectEqual(
            ranks,
            ["com.apple.dt.Xcode": 0, safari: 1, "site:youtube.com": 2],
            "rank = index in the promoted rows, most used first"
        )
    }

    test("dayTotals sums matching site segments per entry and per browser") {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let segments = [
            ActivitySegment(
                kind: .site(domain: "m.youtube.com", browserBundleID: safari),
                start: base, end: base + 100
            ),
            ActivitySegment(
                kind: .site(domain: "youtube.com", browserBundleID: chrome),
                start: base + 100, end: base + 160
            ),
            ActivitySegment(
                kind: .site(domain: "apple.com", browserBundleID: safari),
                start: base + 200, end: base + 260
            ),
            ActivitySegment(
                kind: .app(bundleID: safari, name: "Safari"),
                start: base, end: base + 400
            ),
        ]
        let totals = SitePromotion.dayTotals(
            siteSegments: segments, promoted: ["youtube.com"], clippedTo: nil
        )
        try expectEqual(
            totals.promotedSeconds, ["youtube.com": 160],
            "subdomain and exact matches merge; other kinds ignored"
        )
        try expectEqual(
            totals.browserReductions, [safari: 100, chrome: 60],
            "each browser's attributed share"
        )
    }

    test("dayTotals clips against focus intervals when given") {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let segments = [
            ActivitySegment(
                kind: .site(domain: "youtube.com", browserBundleID: safari),
                start: base, end: base + 100
            ),
            ActivitySegment(
                kind: .site(domain: "youtube.com", browserBundleID: safari),
                start: base + 500, end: base + 600
            ),
        ]
        let focus = [FocusInterval(start: base + 50, end: base + 80)]
        let totals = SitePromotion.dayTotals(
            siteSegments: segments, promoted: ["youtube.com"], clippedTo: focus
        )
        try expectEqual(totals.promotedSeconds, ["youtube.com": 30], "only the overlap counts")
        try expectEqual(totals.browserReductions, [safari: 30], "reduction clipped too")
    }

    test("sparkSeries adds promoted bars and reduces browser bars per day") {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let day0 = [ActivitySegment(
            kind: .site(domain: "youtube.com", browserBundleID: safari),
            start: base, end: base + 40
        )]
        let series = SitePromotion.sparkSeries(
            base: [safari: [100, 200], "com.apple.dt.Xcode": [50, 50]],
            days: [(siteSegments: day0, clip: nil), (siteSegments: [], clip: nil)],
            promoted: ["youtube.com"]
        )
        try expectEqual(series["site:youtube.com"], [40, 0], "promoted series per day")
        try expectEqual(series[safari], [60, 200], "browser bars reduced on the promoted day")
        try expectEqual(series["com.apple.dt.Xcode"], [50, 50], "other apps untouched")
    }

    test("sparkSeries clamps browser bars at zero and skips unknown browsers") {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let day0 = [
            ActivitySegment(
                kind: .site(domain: "youtube.com", browserBundleID: safari),
                start: base, end: base + 50
            ),
            ActivitySegment(
                kind: .site(domain: "youtube.com", browserBundleID: chrome),
                start: base, end: base + 20
            ),
        ]
        let series = SitePromotion.sparkSeries(
            base: [safari: [30]],
            days: [(siteSegments: day0, clip: nil)],
            promoted: ["youtube.com"]
        )
        try expectEqual(series["site:youtube.com"], [70], "cross-browser sum per day")
        try expectEqual(series[safari], [0], "reduction clamps at 0")
        try expectNil(series[chrome], "no bars invented for browsers without a base series")
    }

    test("sparkSeries with empty promoted list returns the base unchanged") {
        let series = SitePromotion.sparkSeries(
            base: [safari: [1, 2]], days: [], promoted: []
        )
        try expectEqual(series, [safari: [1, 2]], "pass-through")
    }

    test("row ids are stable and recognizable") {
        try expectEqual(SitePromotion.rowID(forDomain: "youtube.com"), "site:youtube.com")
        try expect(
            SitePromotion.isPromotedRowID("site:youtube.com"),
            "promoted ids are recognized"
        )
        try expect(
            !SitePromotion.isPromotedRowID("com.apple.Safari"),
            "bundle ids are not promoted ids"
        )
    }

    test("row ids resolve back to their domain") {
        try expectEqual(
            SitePromotion.domain(forRowID: "site:youtube.com"), "youtube.com",
            "the v19 drill-down reads the selected domain off the row id"
        )
        try expectNil(
            SitePromotion.domain(forRowID: "com.apple.Safari"),
            "app selections carry no domain"
        )
        try expectNil(
            SitePromotion.domain(forRowID: "site:"), "an empty domain is no domain"
        )
    }
}
