import Foundation
import TimerCore

/// Offsets in seconds from a fixed base date — the carving math only cares
/// about relative positions.
private let carveBase = Date(timeIntervalSinceReferenceDate: 2_000_000)

private func carveSpan(_ from: Double, _ to: Double) -> SpanCarving.Span {
    SpanCarving.Span(start: carveBase + from, end: carveBase + to)
}

private func carveFocus(_ from: Double, _ to: Double) -> FocusInterval {
    FocusInterval(start: carveBase + from, end: carveBase + to)
}

func runSpanCarvingTests() {
    test("a cut that does not overlap leaves the span whole") {
        try expectEqual(
            SpanCarving.subtract(span: carveSpan(100, 200), minus: [carveSpan(300, 400)]),
            [carveSpan(100, 200)],
            "a cut after the span changes nothing"
        )
        try expectEqual(
            SpanCarving.subtract(span: carveSpan(100, 200), minus: [carveSpan(0, 50)]),
            [carveSpan(100, 200)],
            "a cut before the span changes nothing"
        )
    }

    test("a cut covering the whole span removes it") {
        try expectEqual(
            SpanCarving.subtract(span: carveSpan(100, 200), minus: [carveSpan(0, 500)]),
            [],
            "fully covered spans draw nothing"
        )
        try expectEqual(
            SpanCarving.subtract(span: carveSpan(100, 200), minus: [carveSpan(100, 200)]),
            [],
            "an exactly matching cut removes the span"
        )
    }

    test("a cut overlapping the left edge leaves the right piece") {
        try expectEqual(
            SpanCarving.subtract(span: carveSpan(100, 200), minus: [carveSpan(50, 150)]),
            [carveSpan(150, 200)],
            "one remainder after the cut"
        )
    }

    test("a cut overlapping the right edge leaves the left piece") {
        try expectEqual(
            SpanCarving.subtract(span: carveSpan(100, 200), minus: [carveSpan(150, 250)]),
            [carveSpan(100, 150)],
            "one remainder before the cut"
        )
    }

    test("a cut inside the span splits it in two") {
        try expectEqual(
            SpanCarving.subtract(span: carveSpan(0, 100), minus: [carveSpan(40, 60)]),
            [carveSpan(0, 40), carveSpan(60, 100)],
            "interior cut yields both surrounding pieces, in order"
        )
    }

    test("several cuts apply in order") {
        try expectEqual(
            SpanCarving.subtract(
                span: carveSpan(0, 1000),
                minus: [carveSpan(100, 200), carveSpan(400, 500), carveSpan(900, 1200)]
            ),
            [carveSpan(0, 100), carveSpan(200, 400), carveSpan(500, 900)],
            "every cut is subtracted from what the previous ones left"
        )
    }

    test("overlapping cuts subtract their union") {
        try expectEqual(
            SpanCarving.subtract(
                span: carveSpan(0, 100),
                minus: [carveSpan(20, 60), carveSpan(40, 80)]
            ),
            [carveSpan(0, 20), carveSpan(80, 100)],
            "overlapping cuts never produce slivers between them"
        )
    }

    test("touching boundaries produce no zero-length pieces") {
        try expectEqual(
            SpanCarving.subtract(span: carveSpan(100, 200), minus: [carveSpan(0, 100)]),
            [carveSpan(100, 200)],
            "a cut ending where the span starts is not an overlap"
        )
        try expectEqual(
            SpanCarving.subtract(span: carveSpan(100, 200), minus: [carveSpan(200, 300)]),
            [carveSpan(100, 200)],
            "a cut starting where the span ends is not an overlap"
        )
        try expectEqual(
            SpanCarving.subtract(span: carveSpan(0, 100), minus: [carveSpan(0, 40)]),
            [carveSpan(40, 100)],
            "a cut flush with the left edge leaves no empty piece"
        )
        try expectEqual(
            SpanCarving.subtract(span: carveSpan(0, 100), minus: [carveSpan(60, 100)]),
            [carveSpan(0, 60)],
            "a cut flush with the right edge leaves no empty piece"
        )
    }

    test("degenerate spans and cuts are ignored") {
        try expectEqual(
            SpanCarving.subtract(span: carveSpan(100, 100), minus: []), [],
            "a zero-length span draws nothing"
        )
        try expectEqual(
            SpanCarving.subtract(span: carveSpan(200, 100), minus: []), [],
            "an inverted span draws nothing"
        )
        try expectEqual(
            SpanCarving.subtract(span: carveSpan(0, 100), minus: [carveSpan(50, 50)]),
            [carveSpan(0, 100)],
            "a zero-length cut removes nothing"
        )
        try expectEqual(
            SpanCarving.subtract(span: carveSpan(0, 100), minus: []),
            [carveSpan(0, 100)],
            "no cuts, no change"
        )
    }

    test("the list convenience carves every span with the same cuts") {
        try expectEqual(
            SpanCarving.subtract(
                spans: [carveSpan(0, 100), carveSpan(200, 300), carveSpan(400, 500)],
                minus: [carveSpan(50, 250)]
            ),
            [carveSpan(0, 50), carveSpan(250, 300), carveSpan(400, 500)],
            "spans keep their order, untouched ones pass through"
        )
        try expectEqual(
            SpanCarving.subtract(spans: [], minus: [carveSpan(0, 100)]), [],
            "no spans, nothing to carve"
        )
    }

    test("intersection returns the shared part, nil when only touching") {
        try expectEqual(
            SpanCarving.intersection(carveSpan(0, 100), carveSpan(60, 200)),
            carveSpan(60, 100),
            "the overlap of two spans"
        )
        try expectNil(
            SpanCarving.intersection(carveSpan(0, 100), carveSpan(100, 200)),
            "a shared boundary is not an overlap"
        )
        try expectNil(
            SpanCarving.intersection(carveSpan(0, 100), carveSpan(200, 300)),
            "disjoint spans do not intersect"
        )
    }

    test("clipping keeps only the parts inside the focus intervals") {
        try expectEqual(
            SpanCarving.clip(
                [carveSpan(0, 1000)],
                to: [carveFocus(100, 200), carveFocus(400, 500)]
            ),
            [carveSpan(100, 200), carveSpan(400, 500)],
            "one span split by two focus windows"
        )
        try expectEqual(
            SpanCarving.clip([carveSpan(0, 100)], to: []), [],
            "no focus time, nothing left"
        )
    }

    // The property the "Nur Fokus-Zeit" path relies on: the timeline clips
    // the promoted spans first and carves the browser segment with them,
    // which must show exactly what carving first and clipping afterwards
    // would (v20 spec).
    test("clip-then-carve equals carve-then-clip") {
        let segment = carveSpan(0, 1000)
        let promoted = [carveSpan(200, 250), carveSpan(350, 650)]
        let focus = [carveFocus(100, 400), carveFocus(600, 900)]
        try expectEqual(
            SpanCarving.subtract(
                spans: SpanCarving.clip([segment], to: focus),
                minus: SpanCarving.clip(promoted, to: focus)
            ),
            SpanCarving.clip(
                SpanCarving.subtract(span: segment, minus: promoted), to: focus
            ),
            "the focus filter and the carve commute"
        )
    }

    test("clip-then-carve equals carve-then-clip across edge layouts") {
        let segment = carveSpan(100, 500)
        let cases: [(promoted: [SpanCarving.Span], focus: [FocusInterval])] = [
            ([carveSpan(100, 500)], [carveFocus(0, 600)]),          // full cover
            ([carveSpan(0, 200)], [carveFocus(150, 300)]),          // cut over the left edge
            ([carveSpan(400, 900)], [carveFocus(100, 500)]),        // cut over the right edge
            ([carveSpan(200, 300)], [carveFocus(200, 300)]),        // focus exactly on the cut
            ([carveSpan(200, 300)], [carveFocus(300, 400)]),        // focus touching the cut
            ([], [carveFocus(150, 450)]),                           // nothing carved
            ([carveSpan(150, 200), carveSpan(190, 260)], []),       // no focus at all
        ]
        for (index, layout) in cases.enumerated() {
            try expectEqual(
                SpanCarving.subtract(
                    spans: SpanCarving.clip([segment], to: layout.focus),
                    minus: SpanCarving.clip(layout.promoted, to: layout.focus)
                ),
                SpanCarving.clip(
                    SpanCarving.subtract(span: segment, minus: layout.promoted),
                    to: layout.focus
                ),
                "layout \(index) commutes"
            )
        }
    }
}
