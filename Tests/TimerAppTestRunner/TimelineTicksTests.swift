import Foundation
import TimerCore

func runTimelineTicksTests() {
    // tickIntervalMinutes: nil = coarse start/mid/end labels, 60 = hourly,
    // 15 = quarter-hourly. Thresholds: hourly needs >= 60 pt per hour,
    // quarter-hourly >= 50 pt per quarter hour; 1x is always coarse.

    test("1x always keeps the coarse start/mid/end labels") {
        try expectNil(
            TimelineTicks.tickIntervalMinutes(zoom: 1, spanMinutes: 480, viewportWidth: 500),
            "8 h day at 1x"
        )
        try expectNil(
            TimelineTicks.tickIntervalMinutes(zoom: 1, spanMinutes: 30, viewportWidth: 2000),
            "short span in a wide window stays coarse at 1x"
        )
        try expectNil(
            TimelineTicks.tickIntervalMinutes(zoom: 0.5, spanMinutes: 480, viewportWidth: 500),
            "below-range zoom clamps up to 1x"
        )
    }

    test("hourly ticks once an hour spans at least 60 points") {
        // 8 h span, 500 pt viewport, 2x: hour = 125 pt, quarter = 31 pt.
        try expectEqual(
            TimelineTicks.tickIntervalMinutes(zoom: 2, spanMinutes: 480, viewportWidth: 500),
            60, "mid zoom on a work day"
        )
        // 12 h span, 400 pt viewport, 1.2x: hour = 40 pt — still coarse.
        try expectNil(
            TimelineTicks.tickIntervalMinutes(zoom: 1.2, spanMinutes: 720, viewportWidth: 400),
            "long span at low zoom"
        )
        // Exactly 60 pt per hour counts as hourly.
        try expectEqual(
            TimelineTicks.tickIntervalMinutes(zoom: 2, spanMinutes: 480, viewportWidth: 240),
            60, "hour exactly at the 60 pt threshold"
        )
    }

    test("quarter-hourly ticks once a quarter hour spans at least 50 points") {
        // 8 h span, 500 pt viewport, 8x: quarter = 125 pt.
        try expectEqual(
            TimelineTicks.tickIntervalMinutes(zoom: 8, spanMinutes: 480, viewportWidth: 500),
            15, "high zoom on a work day"
        )
        // Exactly 50 pt per quarter hour counts as quarter-hourly.
        try expectEqual(
            TimelineTicks.tickIntervalMinutes(zoom: 16, spanMinutes: 480, viewportWidth: 100),
            15, "quarter exactly at the 50 pt threshold"
        )
        // A short span reaches quarter-hour density at low zoom already.
        try expectEqual(
            TimelineTicks.tickIntervalMinutes(zoom: 2, spanMinutes: 30, viewportWidth: 400),
            15, "half-hour span at 2x"
        )
    }

    test("zoom input clamps to the 16x maximum") {
        // 24 h span, 100 pt viewport at 16x: hour = 66.7 pt, quarter = 16.7 pt.
        try expectEqual(
            TimelineTicks.tickIntervalMinutes(zoom: 16, spanMinutes: 1440, viewportWidth: 100),
            60, "full day at the max zoom"
        )
        // Unclamped 64x would reach quarter-hour density; clamped it stays hourly.
        try expectEqual(
            TimelineTicks.tickIntervalMinutes(zoom: 64, spanMinutes: 1440, viewportWidth: 100),
            60, "overshoot zoom behaves like 16x"
        )
    }

    test("degenerate span or width falls back to coarse") {
        try expectNil(
            TimelineTicks.tickIntervalMinutes(zoom: 4, spanMinutes: 0, viewportWidth: 500),
            "empty span"
        )
        try expectNil(
            TimelineTicks.tickIntervalMinutes(zoom: 4, spanMinutes: -10, viewportWidth: 500),
            "negative span"
        )
        try expectNil(
            TimelineTicks.tickIntervalMinutes(zoom: 4, spanMinutes: 480, viewportWidth: 0),
            "zero-width viewport"
        )
    }

    // tickOffsetsMinutes: offsets from the span start for every wall-clock
    // multiple of the interval inside the span, boundaries included.

    test("tick offsets land on wall-clock multiples of the interval") {
        // Day starts 9:07:30 (547.5 min), 2 h span, hourly: 10:00 and 11:00.
        try expectEqual(
            TimelineTicks.tickOffsetsMinutes(startMinuteOfDay: 547.5, spanMinutes: 120, intervalMinutes: 60),
            [52.5, 112.5], "hourly ticks from a mid-hour start"
        )
        // A start exactly on a boundary keeps the offset-zero tick, and the
        // span-end boundary is included too.
        try expectEqual(
            TimelineTicks.tickOffsetsMinutes(startMinuteOfDay: 540, spanMinutes: 60, intervalMinutes: 15),
            [0, 15, 30, 45, 60], "quarter ticks including both edges"
        )
    }

    test("tick offsets guard degenerate input") {
        try expectEqual(
            TimelineTicks.tickOffsetsMinutes(startMinuteOfDay: 540, spanMinutes: 0, intervalMinutes: 15),
            [], "empty span"
        )
        try expectEqual(
            TimelineTicks.tickOffsetsMinutes(startMinuteOfDay: 540, spanMinutes: 60, intervalMinutes: 0),
            [], "non-positive interval"
        )
        try expectEqual(
            TimelineTicks.tickOffsetsMinutes(startMinuteOfDay: .infinity, spanMinutes: 60, intervalMinutes: 15),
            [], "non-finite start"
        )
    }
}
