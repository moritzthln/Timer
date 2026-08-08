import Foundation
import TimerCore

/// Offsets in seconds from a fixed base date — the clip math only cares
/// about relative positions.
private let clipBase = Date(timeIntervalSinceReferenceDate: 1_000_000)

private func at(_ seconds: Double) -> Date {
    clipBase.addingTimeInterval(seconds)
}

private func focus(_ start: Double, _ end: Double) -> FocusInterval {
    FocusInterval(start: at(start), end: at(end))
}

private func clipped(_ start: Double, _ end: Double, _ intervals: [FocusInterval]) -> Double {
    FocusClip.clippedSeconds(segmentStart: at(start), segmentEnd: at(end), intervals: intervals)
}

func runFocusClipTests() {
    test("empty interval list clips to zero") {
        try expectEqual(clipped(0, 100, []), 0, accuracy: 0.001, "no intervals")
    }

    test("interval entirely before the segment counts nothing") {
        try expectEqual(clipped(100, 200, [focus(0, 50)]), 0, accuracy: 0.001, "before")
    }

    test("interval entirely after the segment counts nothing") {
        try expectEqual(clipped(0, 50, [focus(100, 200)]), 0, accuracy: 0.001, "after")
    }

    test("segment fully inside one interval counts the whole segment") {
        try expectEqual(clipped(100, 160, [focus(50, 300)]), 60, accuracy: 0.001, "contained segment")
    }

    test("interval fully inside the segment counts the whole interval") {
        try expectEqual(clipped(0, 600, [focus(100, 250)]), 150, accuracy: 0.001, "contained interval")
    }

    test("partial overlap on the left clips to the shared part") {
        try expectEqual(clipped(100, 300, [focus(50, 180)]), 80, accuracy: 0.001, "left overlap")
    }

    test("partial overlap on the right clips to the shared part") {
        try expectEqual(clipped(100, 300, [focus(250, 400)]), 50, accuracy: 0.001, "right overlap")
    }

    test("segment spanning multiple intervals sums the pieces") {
        let intervals = [focus(100, 200), focus(300, 450), focus(900, 1200)]
        try expectEqual(clipped(0, 1000, intervals), 350, accuracy: 0.001, "multi-interval span")
    }

    test("zero-length segment counts nothing") {
        try expectEqual(clipped(100, 100, [focus(0, 1000)]), 0, accuracy: 0.001, "zero-length segment")
    }

    test("inverted segment counts nothing") {
        try expectEqual(clipped(200, 100, [focus(0, 1000)]), 0, accuracy: 0.001, "inverted segment")
    }

    test("zero-length interval adds nothing") {
        try expectEqual(clipped(0, 100, [focus(50, 50)]), 0, accuracy: 0.001, "zero-length interval")
    }

    test("interval touching the segment start adds nothing") {
        try expectEqual(clipped(100, 200, [focus(0, 100)]), 0, accuracy: 0.001, "touches start")
    }

    test("interval touching the segment end adds nothing") {
        try expectEqual(clipped(100, 200, [focus(200, 300)]), 0, accuracy: 0.001, "touches end")
    }

    test("touching intervals cover the segment without double counting") {
        try expectEqual(clipped(0, 100, [focus(0, 50), focus(50, 100)]), 100, accuracy: 0.001, "touching boundary")
    }
}
