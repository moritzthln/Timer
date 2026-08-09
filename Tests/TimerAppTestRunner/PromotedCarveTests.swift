import Foundation
import TimerCore

private let carveDay = Date(timeIntervalSinceReferenceDate: 3_000_000)
private let safariID = "com.apple.Safari"
private let chromeID = "com.google.Chrome"

private func visit(
    _ domain: String, _ from: Double, _ to: Double, browser: String = "com.apple.Safari"
) -> ActivitySegment {
    ActivitySegment(
        kind: .site(domain: domain, browserBundleID: browser),
        start: carveDay + from, end: carveDay + to
    )
}

private func piece(_ from: Double, _ to: Double) -> SpanCarving.Span {
    SpanCarving.Span(start: carveDay + from, end: carveDay + to)
}

private func entry(_ domain: String, _ spans: [SpanCarving.Span]) -> PromotedCarve.Entry {
    PromotedCarve.Entry(domain: domain, spans: spans)
}

func runPromotedCarveTests() {
    test("a browser's promoted spans become its cuts") {
        let carve = PromotedCarve(
            siteSegments: [visit("youtube.com", 100, 200), visit("apple.com", 300, 400)],
            promoted: ["youtube.com"], clippedTo: nil
        )
        try expectEqual(
            carve.cuts(browser: safariID), [piece(100, 200)],
            "only promoted domains cut, other sites stay inside the browser"
        )
    }

    test("cuts stay inside the browser that produced them") {
        let carve = PromotedCarve(
            siteSegments: [visit("youtube.com", 100, 200, browser: chromeID)],
            promoted: ["youtube.com"], clippedTo: nil
        )
        try expectEqual(
            carve.cuts(browser: chromeID), [piece(100, 200)], "Chrome owns its own visit"
        )
        try expectEqual(
            carve.cuts(browser: safariID), [],
            "Safari's bar is never carved by Chrome's YouTube time"
        )
    }

    test("nothing promoted carves nothing") {
        let carve = PromotedCarve(
            siteSegments: [visit("youtube.com", 100, 200)], promoted: [], clippedTo: nil
        )
        try expectEqual(carve.cuts(browser: safariID), [], "empty promoted list, empty table")
        try expectEqual(
            carve.pieces(browser: safariID, in: piece(0, 1000)), [], "and no carved pieces"
        )
    }

    test("subdomains and repeat visits merge into one span per domain") {
        let carve = PromotedCarve(
            siteSegments: [
                visit("m.youtube.com", 100, 150),
                visit("youtube.com", 150, 200),
                visit("youtube.com", 400, 450),
            ],
            promoted: ["youtube.com"], clippedTo: nil
        )
        try expectEqual(
            carve.cuts(browser: safariID), [piece(100, 200), piece(400, 450)],
            "touching visits read as one, gaps stay gaps"
        )
    }

    test("pieces are tagged with the promoted domain that owns them") {
        let carve = PromotedCarve(
            siteSegments: [
                visit("youtube.com", 100, 200), visit("instagram.com", 300, 400),
            ],
            promoted: ["instagram.com", "youtube.com"], clippedTo: nil
        )
        try expectEqual(
            carve.pieces(browser: safariID, in: piece(0, 1000)),
            [entry("instagram.com", [piece(300, 400)]), entry("youtube.com", [piece(100, 200)])],
            "one entry per promoted domain, in promoted-list order"
        )
    }

    test("pieces are trimmed to the carved app segment") {
        let carve = PromotedCarve(
            siteSegments: [visit("youtube.com", 100, 400)],
            promoted: ["youtube.com"], clippedTo: nil
        )
        try expectEqual(
            carve.pieces(browser: safariID, in: piece(200, 300)),
            [entry("youtube.com", [piece(200, 300)])],
            "a span reaching past the segment is clipped to it"
        )
        try expectEqual(
            carve.pieces(browser: safariID, in: piece(500, 600)), [],
            "a segment without promoted time carves nothing"
        )
        try expectEqual(
            carve.pieces(browser: safariID, in: piece(400, 500)), [],
            "a segment touching the span's end is not an overlap"
        )
    }

    test("overlapping promoted entries: the first in list order owns the time") {
        let segments = [visit("m.youtube.com", 100, 200)]
        try expectEqual(
            PromotedCarve(
                siteSegments: segments, promoted: ["youtube.com", "m.youtube.com"],
                clippedTo: nil
            ).pieces(browser: safariID, in: piece(0, 1000)),
            [entry("youtube.com", [piece(100, 200)])],
            "the broad entry first owns it — same rule as the list rows"
        )
        try expectEqual(
            PromotedCarve(
                siteSegments: segments, promoted: ["m.youtube.com", "youtube.com"],
                clippedTo: nil
            ).pieces(browser: safariID, in: piece(0, 1000)),
            [entry("m.youtube.com", [piece(100, 200)])],
            "the specific entry owns it, the broad row carves nothing"
        )
    }

    test("the focus filter clips the cuts before they carve") {
        let carve = PromotedCarve(
            siteSegments: [visit("youtube.com", 100, 400)],
            promoted: ["youtube.com"],
            clippedTo: [FocusInterval(start: carveDay + 200, end: carveDay + 300)]
        )
        try expectEqual(
            carve.cuts(browser: safariID), [piece(200, 300)],
            "only the focus part of the visit carves the bar"
        )
        try expectEqual(
            SpanCarving.subtract(span: piece(0, 500), minus: carve.cuts(browser: safariID)),
            [piece(0, 200), piece(300, 500)],
            "the browser keeps everything outside the focus window"
        )
    }

    test("an empty focus list clips every cut away") {
        let carve = PromotedCarve(
            siteSegments: [visit("youtube.com", 100, 400)],
            promoted: ["youtube.com"], clippedTo: []
        )
        try expectEqual(
            carve.cuts(browser: safariID), [],
            "no focus time means nothing is carved (nil would mean unfiltered)"
        )
    }
}
