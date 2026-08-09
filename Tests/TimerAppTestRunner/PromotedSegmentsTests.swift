import Foundation
import TimerCore

private let base = Date(timeIntervalSince1970: 1_000_000)
private let safari = "com.apple.Safari"
private let chrome = "com.google.Chrome"

private func site(
    _ domain: String, _ from: Double, _ to: Double, browser: String = "com.apple.Safari"
) -> ActivitySegment {
    ActivitySegment(
        kind: .site(domain: domain, browserBundleID: browser),
        start: base + from, end: base + to
    )
}

private func span(_ from: Double, _ to: Double) -> PromotedSegments.Span {
    PromotedSegments.Span(start: base + from, end: base + to)
}

func runPromotedSegmentsTests() {
    test("only site segments of the domain become spans") {
        let segments = [
            site("youtube.com", 0, 100),
            site("apple.com", 200, 300),
            ActivitySegment(
                kind: .app(bundleID: safari, name: "Safari"), start: base, end: base + 500
            ),
            ActivitySegment(kind: .presence, start: base, end: base + 500),
        ]
        try expectEqual(
            PromotedSegments.spans(siteSegments: segments, domain: "youtube.com"),
            [span(0, 100)],
            "other domains and other segment kinds are ignored"
        )
    }

    test("subdomains match, lookalike domains do not") {
        let segments = [
            site("m.youtube.com", 0, 60),
            site("notyoutube.com", 100, 160),
            site("YouTube.com", 200, 260),
        ]
        try expectEqual(
            PromotedSegments.spans(siteSegments: segments, domain: "youtube.com"),
            [span(0, 60), span(200, 260)],
            "suffix matching with the blocker's semantics, case-insensitive"
        )
    }

    test("spans merge across browsers and sort by start") {
        let segments = [
            site("youtube.com", 300, 360, browser: chrome),
            site("m.youtube.com", 100, 160),
            site("youtube.com", 0, 50, browser: chrome),
        ]
        try expectEqual(
            PromotedSegments.spans(siteSegments: segments, domain: "youtube.com"),
            [span(0, 50), span(100, 160), span(300, 360)],
            "one merged, chronologically sorted list regardless of browser"
        )
    }

    test("touching and overlapping spans collapse into one") {
        let segments = [
            site("youtube.com", 0, 100),
            site("m.youtube.com", 100, 150, browser: chrome),
            site("youtube.com", 120, 200),
            site("youtube.com", 400, 450),
        ]
        try expectEqual(
            PromotedSegments.spans(siteSegments: segments, domain: "youtube.com"),
            [span(0, 200), span(400, 450)],
            "adjacent and overlapping pieces read as one visit, gaps stay gaps"
        )
    }

    test("empty and degenerate segments produce no spans") {
        let segments = [
            site("youtube.com", 100, 100),
            site("youtube.com", 300, 200),
        ]
        try expectEqual(
            PromotedSegments.spans(siteSegments: segments, domain: "youtube.com"), [],
            "zero-length and inverted segments are dropped"
        )
        try expectEqual(
            PromotedSegments.spans(siteSegments: [], domain: "youtube.com"), [],
            "no segments, no spans"
        )
    }

    test("overlapping promoted entries: the first entry in list order owns the segment") {
        let segments = [site("m.youtube.com", 0, 100)]
        try expectEqual(
            PromotedSegments.spans(
                siteSegments: segments, domain: "youtube.com",
                promoted: ["youtube.com", "m.youtube.com"]
            ),
            [span(0, 100)],
            "broad entry first owns it — same rule as the row totals"
        )
        try expectEqual(
            PromotedSegments.spans(
                siteSegments: segments, domain: "youtube.com",
                promoted: ["m.youtube.com", "youtube.com"]
            ),
            [],
            "the specific entry owns it, so the broad row highlights nothing"
        )
    }

    test("a domain outside the promoted list owns nothing") {
        let segments = [site("youtube.com", 0, 100)]
        try expectEqual(
            PromotedSegments.spans(
                siteSegments: segments, domain: "youtube.com", promoted: ["instagram.com"]
            ),
            [],
            "a domain outside the promoted list owns nothing"
        )
    }

    test("clipping keeps only the overlap with the focus intervals") {
        let segments = [
            site("youtube.com", 0, 100),
            site("youtube.com", 500, 600),
        ]
        let focus = [
            FocusInterval(start: base + 50, end: base + 80),
            FocusInterval(start: base + 700, end: base + 800),
        ]
        try expectEqual(
            PromotedSegments.spans(
                siteSegments: segments, domain: "youtube.com", clippedTo: focus
            ),
            [span(50, 80)],
            "spans outside every focus window disappear, the rest is trimmed"
        )
    }

    test("one span split by two focus windows yields two pieces") {
        let segments = [site("youtube.com", 0, 1000)]
        let focus = [
            FocusInterval(start: base + 100, end: base + 200),
            FocusInterval(start: base + 400, end: base + 500),
        ]
        try expectEqual(
            PromotedSegments.spans(
                siteSegments: segments, domain: "youtube.com", clippedTo: focus
            ),
            [span(100, 200), span(400, 500)],
            "the gap between focus windows breaks the span"
        )
    }

    test("touching focus boundaries contribute nothing") {
        let segments = [site("youtube.com", 100, 200)]
        let focus = [FocusInterval(start: base + 200, end: base + 300)]
        try expectEqual(
            PromotedSegments.spans(
                siteSegments: segments, domain: "youtube.com", clippedTo: focus
            ),
            [],
            "FocusClip semantics: a shared boundary is not an overlap"
        )
    }

    test("an empty focus list clips everything away") {
        let segments = [site("youtube.com", 0, 100)]
        try expectEqual(
            PromotedSegments.spans(
                siteSegments: segments, domain: "youtube.com", clippedTo: []
            ),
            [],
            "no focus time, no highlighted spans (nil would mean unfiltered)"
        )
    }
}
