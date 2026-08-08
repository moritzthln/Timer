import Foundation
import TimerCore

func runWeekRankingTests() {
    test("ranks apps by total descending") {
        let ranks = WeekRanking.rank(appTotals: [
            "com.small": 60,
            "com.big": 3600,
            "com.mid": 600,
        ])
        try expectEqual(ranks["com.big"], 0, "biggest first")
        try expectEqual(ranks["com.mid"], 1, "middle second")
        try expectEqual(ranks["com.small"], 2, "smallest last")
    }

    test("equal totals break ties by bundle id for stable colors") {
        let ranks = WeekRanking.rank(appTotals: ["b.app": 100, "a.app": 100, "c.app": 100])
        try expectEqual(ranks["a.app"], 0, "a before b")
        try expectEqual(ranks["b.app"], 1, "b before c")
        try expectEqual(ranks["c.app"], 2, "c last")
    }

    test("empty totals rank as empty") {
        try expectEqual(WeekRanking.rank(appTotals: [:]).isEmpty, true, "empty")
    }

    test("ranks are contiguous starting at zero") {
        let ranks = WeekRanking.rank(appTotals: ["a": 5, "b": 4, "c": 3, "d": 2])
        try expectEqual(ranks.values.sorted(), [0, 1, 2, 3], "contiguous")
    }
}
