import Foundation
import TimerCore

func runUsageShareTests() {
    test("zero total yields no label") {
        try expectNil(UsageShare.percentLabel(seconds: 120, total: 0), "basis 0")
        try expectNil(UsageShare.percentLabel(seconds: 0, total: 0), "all zero")
    }

    test("zero seconds yield no label") {
        try expectNil(UsageShare.percentLabel(seconds: 0, total: 3600), "0 s row")
    }

    test("shares round to whole percents") {
        try expectEqual(UsageShare.percentLabel(seconds: 390, total: 1000), "39 %", "39.0")
        try expectEqual(UsageShare.percentLabel(seconds: 384, total: 1000), "38 %", "38.4 down")
        try expectEqual(UsageShare.percentLabel(seconds: 386, total: 1000), "39 %", "38.6 up")
    }

    test("exact halves round up") {
        // 125/1000 = 1/8 is binary-exact, so the percent is exactly 12.5.
        try expectEqual(UsageShare.percentLabel(seconds: 125, total: 1000), "13 %", "12.5")
    }

    test("tiny but nonzero shares render as below one percent") {
        try expectEqual(UsageShare.percentLabel(seconds: 4, total: 1000), "<1 %", "0.4")
        try expectEqual(UsageShare.percentLabel(seconds: 1, total: 100000), "<1 %", "0.001")
    }

    test("shares at or above half a percent round to one") {
        try expectEqual(UsageShare.percentLabel(seconds: 6, total: 1000), "1 %", "0.6")
        try expectEqual(UsageShare.percentLabel(seconds: 1, total: 128), "1 %", "0.78125")
    }

    test("the full basis is one hundred percent") {
        try expectEqual(UsageShare.percentLabel(seconds: 2412, total: 2412), "100 %", "whole")
    }
}
