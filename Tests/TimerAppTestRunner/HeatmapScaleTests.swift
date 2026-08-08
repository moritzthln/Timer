import Foundation
import TimerCore

func runHeatmapScaleTests() {
    test("zero seconds is level zero regardless of the period max") {
        try expectEqual(HeatmapScale.level(seconds: 0, maxSeconds: 10000), 0, "empty day")
        try expectEqual(HeatmapScale.level(seconds: 0, maxSeconds: 0), 0, "empty period")
        try expectEqual(HeatmapScale.level(seconds: -5, maxSeconds: 10000), 0, "negative treated as empty")
    }

    test("levels split at quarter, half, and three-quarter of the period max") {
        try expectEqual(HeatmapScale.level(seconds: 1, maxSeconds: 10000), 1, "any activity below 25 %")
        try expectEqual(HeatmapScale.level(seconds: 2499, maxSeconds: 10000), 1, "just below 25 %")
        try expectEqual(HeatmapScale.level(seconds: 2500, maxSeconds: 10000), 2, "exactly 25 %")
        try expectEqual(HeatmapScale.level(seconds: 4999, maxSeconds: 10000), 2, "just below 50 %")
        try expectEqual(HeatmapScale.level(seconds: 5000, maxSeconds: 10000), 3, "exactly 50 %")
        try expectEqual(HeatmapScale.level(seconds: 7499, maxSeconds: 10000), 3, "just below 75 %")
        try expectEqual(HeatmapScale.level(seconds: 7500, maxSeconds: 10000), 4, "exactly 75 %")
        try expectEqual(HeatmapScale.level(seconds: 10000, maxSeconds: 10000), 4, "the max itself")
    }

    test("degenerate period max treats any activity as full intensity") {
        // maxSeconds is the max over a period that includes the day itself, so
        // seconds > max cannot happen in real use; guard the division anyway.
        try expectEqual(HeatmapScale.level(seconds: 60, maxSeconds: 0), 4, "positive seconds, zero max")
    }
}
