import Foundation
import TimerCore

func runSiteCoverPlanTests() {
    let base = Date(timeIntervalSince1970: 1_000_000)

    test("the first sight of a blocked host raises the cover") {
        let decision = SiteCoverPlan.next(
            host: "instagram.com", coveredHost: nil, coveredSince: nil,
            now: base, threshold: 10
        )
        try expectEqual(decision, .cover(host: "instagram.com"), "first sight covers")
    }

    test("the same host under the threshold keeps the cover") {
        let decision = SiteCoverPlan.next(
            host: "instagram.com", coveredHost: "instagram.com",
            coveredSince: base, now: base.addingTimeInterval(9.5), threshold: 10
        )
        try expectEqual(decision, .keepCovering, "9.5 s is still inside the grace")
    }

    test("the threshold itself already switches away") {
        let decision = SiteCoverPlan.next(
            host: "instagram.com", coveredHost: "instagram.com",
            coveredSince: base, now: base.addingTimeInterval(10), threshold: 10
        )
        try expectEqual(decision, .switchAway, "the boundary belongs to the switch")
    }

    test("staying past the threshold switches away") {
        let decision = SiteCoverPlan.next(
            host: "instagram.com", coveredHost: "instagram.com",
            coveredSince: base, now: base.addingTimeInterval(30), threshold: 10
        )
        try expectEqual(decision, .switchAway, "past the threshold the tab switch runs")
    }

    test("another blocked host restarts the clock instead of switching") {
        let decision = SiteCoverPlan.next(
            host: "youtube.com", coveredHost: "instagram.com",
            coveredSince: base, now: base.addingTimeInterval(60), threshold: 10
        )
        try expectEqual(
            decision, .cover(host: "youtube.com"),
            "a different host gets its own 10 s, however long the previous one ran"
        )
    }

    test("a host that is no longer blocked drops the cover") {
        let decision = SiteCoverPlan.next(
            host: nil, coveredHost: "instagram.com",
            coveredSince: base, now: base.addingTimeInterval(3), threshold: 10
        )
        try expectEqual(decision, .dropCover, "nothing blocked means nothing covered")
    }

    test("no host and no cover stays at drop") {
        let decision = SiteCoverPlan.next(
            host: nil, coveredHost: nil, coveredSince: nil, now: base, threshold: 10
        )
        try expectEqual(decision, .dropCover, "the idle answer is the idempotent teardown")
    }

    test("a covered host without a start time is covered again") {
        let decision = SiteCoverPlan.next(
            host: "instagram.com", coveredHost: "instagram.com",
            coveredSince: nil, now: base, threshold: 10
        )
        try expectEqual(
            decision, .cover(host: "instagram.com"),
            "inconsistent state restarts rather than switching instantly"
        )
    }

    test("a clock jumping backwards keeps covering") {
        let decision = SiteCoverPlan.next(
            host: "instagram.com", coveredHost: "instagram.com",
            coveredSince: base, now: base.addingTimeInterval(-120), threshold: 10
        )
        try expectEqual(decision, .keepCovering, "a negative age never counts as elapsed")
    }
}
