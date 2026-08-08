import Foundation
import TimerCore

func runPresenceRulesTests() {
    test("present only when unlocked, awake, unpaused, and recently active") {
        try expect(PresenceRules.isPresent(
            lastInputAge: 10, thresholdSeconds: 300,
            screenLocked: false, asleep: false, paused: false
        ), "normal activity")
        try expect(!PresenceRules.isPresent(
            lastInputAge: 301, thresholdSeconds: 300,
            screenLocked: false, asleep: false, paused: false
        ), "idle past threshold")
        try expect(!PresenceRules.isPresent(
            lastInputAge: 10, thresholdSeconds: 300,
            screenLocked: true, asleep: false, paused: false
        ), "locked")
        try expect(!PresenceRules.isPresent(
            lastInputAge: 10, thresholdSeconds: 300,
            screenLocked: false, asleep: true, paused: false
        ), "asleep")
        try expect(!PresenceRules.isPresent(
            lastInputAge: 10, thresholdSeconds: 300,
            screenLocked: false, asleep: false, paused: true
        ), "paused")
    }

    test("site host normalization strips www and lowercases") {
        try expectEqual(ActivitySegment.normalizeHost("WWW.YouTube.com"), "youtube.com", "www stripped")
        try expectEqual(ActivitySegment.normalizeHost("docs.google.com"), "docs.google.com", "subdomain kept")
        try expectEqual(ActivitySegment.normalizeHost("www.docs.google.com"), "docs.google.com", "leading www only")
    }
}
