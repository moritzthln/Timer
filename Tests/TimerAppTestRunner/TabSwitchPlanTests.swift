import Foundation
import TimerCore

func runTabSwitchPlanTests() {
    test("middle tab switches to the right neighbor") {
        var probed: [Int] = []
        let target = TabSwitchPlan.target(activeIndex: 2, count: 4) { index in
            probed.append(index)
            return false
        }
        try expectEqual(target, .neighbor(index: 3), "middle tab prefers index+1")
        try expectEqual(probed, [3], "exactly one neighbor probe, on the chosen index")
    }

    test("first tab switches to the right neighbor") {
        let target = TabSwitchPlan.target(activeIndex: 1, count: 3) { _ in false }
        try expectEqual(target, .neighbor(index: 2), "first tab prefers index+1")
    }

    test("last tab falls back to the left neighbor") {
        var probed: [Int] = []
        let target = TabSwitchPlan.target(activeIndex: 3, count: 3) { index in
            probed.append(index)
            return false
        }
        try expectEqual(target, .neighbor(index: 2), "last tab uses index-1")
        try expectEqual(probed, [2], "the left neighbor is the one probed")
    }

    test("only tab opens a new tab without probing") {
        var probeCount = 0
        let target = TabSwitchPlan.target(activeIndex: 1, count: 1) { _ in
            probeCount += 1
            return false
        }
        try expectEqual(target, .newTab, "only tab means a new empty tab")
        try expectEqual(probeCount, 0, "no neighbor exists, so no probe")
    }

    test("blocked neighbor opens a new tab instead") {
        var probed: [Int] = []
        let target = TabSwitchPlan.target(activeIndex: 2, count: 3) { index in
            probed.append(index)
            return true
        }
        try expectEqual(target, .newTab, "one extra read, then new tab — no second neighbor try")
        try expectEqual(probed, [3], "only the preferred neighbor is probed")
    }

    test("count and index guards degrade to a new tab") {
        var probeCount = 0
        let probe: (Int) -> Bool = { _ in
            probeCount += 1
            return false
        }
        try expectEqual(
            TabSwitchPlan.target(activeIndex: 1, count: 0, neighborBlocked: probe),
            .newTab, "zero tabs"
        )
        try expectEqual(
            TabSwitchPlan.target(activeIndex: 0, count: 3, neighborBlocked: probe),
            .newTab, "index below the 1-based range"
        )
        try expectEqual(
            TabSwitchPlan.target(activeIndex: 4, count: 3, neighborBlocked: probe),
            .newTab, "index beyond the count"
        )
        try expectEqual(probeCount, 0, "degenerate geometry never probes")
    }
}
