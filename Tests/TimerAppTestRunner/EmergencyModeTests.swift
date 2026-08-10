import Foundation
import TimerCore

private func freshEmergencyPrefs() -> Preferences {
    let suite = "EmergencyModeTests"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return Preferences(defaults: defaults)
}

func runEmergencyModeTests() {
    let anchor = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Clamping

    test("emergency minutes clamp to 1...60") {
        try expectEqual(EmergencyMode.clamp(minutes: 0), 1, "zero clamps up")
        try expectEqual(EmergencyMode.clamp(minutes: -5), 1, "negative clamps up")
        try expectEqual(EmergencyMode.clamp(minutes: 1), 1, "lower bound stays")
        try expectEqual(EmergencyMode.clamp(minutes: 25), 25, "default passes through")
        try expectEqual(EmergencyMode.clamp(minutes: 60), 60, "upper bound stays")
        try expectEqual(EmergencyMode.clamp(minutes: 61), 60, "one over clamps down")
        try expectEqual(EmergencyMode.clamp(minutes: 999), 60, "far over clamps down")
    }

    test("start clamps the duration into the end date") {
        try expectEqual(
            EmergencyMode.start(minutes: 25, now: anchor).endDate,
            anchor.addingTimeInterval(1500), "25 min"
        )
        try expectEqual(
            EmergencyMode.start(minutes: 999, now: anchor).endDate,
            anchor.addingTimeInterval(3600), "the hard cap is enforced in the model"
        )
        try expectEqual(
            EmergencyMode.start(minutes: 0, now: anchor).endDate,
            anchor.addingTimeInterval(60), "zero still yields a real minute"
        )
    }

    // MARK: - Activity around the boundary

    test("a session is active until its end date, never after") {
        let session = EmergencyMode.start(minutes: 1, now: anchor)
        try expect(EmergencyMode.isActive(session: session, now: anchor), "active at the start")
        try expect(
            EmergencyMode.isActive(session: session, now: anchor.addingTimeInterval(59)),
            "active one second before the end"
        )
        try expect(
            !EmergencyMode.isActive(session: session, now: anchor.addingTimeInterval(60)),
            "the end date itself is over"
        )
        try expect(
            !EmergencyMode.isActive(session: session, now: anchor.addingTimeInterval(600)),
            "long past the end"
        )
    }

    test("no session means never active") {
        try expect(!EmergencyMode.isActive(session: nil, now: anchor), "nil is inactive")
        try expectEqual(EmergencyMode.remainingSeconds(session: nil, now: anchor), 0, "nil has no time")
    }

    // MARK: - Remaining seconds

    test("remaining seconds count down and never go negative") {
        let session = EmergencyMode.start(minutes: 25, now: anchor)
        try expectEqual(
            EmergencyMode.remainingSeconds(session: session, now: anchor), 1500, "full duration"
        )
        try expectEqual(
            EmergencyMode.remainingSeconds(session: session, now: anchor.addingTimeInterval(23)),
            1477, "counted down"
        )
        try expectEqual(
            EmergencyMode.remainingSeconds(session: session, now: anchor.addingTimeInterval(1499.5)),
            1, "a partial second rounds up, like the engine"
        )
        try expectEqual(
            EmergencyMode.remainingSeconds(session: session, now: anchor.addingTimeInterval(1500)),
            0, "zero at the end"
        )
        try expectEqual(
            EmergencyMode.remainingSeconds(session: session, now: anchor.addingTimeInterval(9000)),
            0, "never negative"
        )
    }

    // MARK: - Persistence

    test("a persisted emergency session survives and reports its remainder") {
        let prefs = freshEmergencyPrefs()
        try expectNil(prefs.emergencySession(now: anchor), "nothing persisted yet")
        let session = prefs.startEmergency(minutes: 10, now: anchor)
        try expectEqual(session.endDate, anchor.addingTimeInterval(600), "clamped end date persisted")
        try expectEqual(
            prefs.emergencySession(now: anchor.addingTimeInterval(120)), session,
            "re-read (relaunch) yields the same session"
        )
        try expectEqual(
            EmergencyMode.remainingSeconds(
                session: prefs.emergencySession(now: anchor.addingTimeInterval(120)),
                now: anchor.addingTimeInterval(120)
            ),
            480, "the remainder continues across the restore"
        )
    }

    test("an elapsed end date reads as inactive and is cleared") {
        let prefs = freshEmergencyPrefs()
        prefs.emergencyEndDate = anchor.addingTimeInterval(-1)
        try expectNil(prefs.emergencySession(now: anchor), "a past end date is no session")
        try expectNil(prefs.emergencyEndDate, "and it is cleared on read")
    }

    test("ending an emergency session clears the persisted end date") {
        let prefs = freshEmergencyPrefs()
        prefs.startEmergency(minutes: 30, now: anchor)
        prefs.endEmergency()
        try expectNil(prefs.emergencyEndDate, "cleared")
        try expectNil(prefs.emergencySession(now: anchor), "and inactive")
    }

    test("starting stores the clamped duration as the new default") {
        let prefs = freshEmergencyPrefs()
        try expectEqual(prefs.emergencyMinutes, 25, "spec default")
        prefs.startEmergency(minutes: 999, now: anchor)
        try expectEqual(prefs.emergencyMinutes, 60, "the clamped value is remembered, not the input")
    }

    test("emergency minutes clamp on write and read") {
        let prefs = freshEmergencyPrefs()
        prefs.emergencyMinutes = 0
        try expectEqual(prefs.emergencyMinutes, 1, "clamped up")
        prefs.emergencyMinutes = 90
        try expectEqual(prefs.emergencyMinutes, 60, "clamped down")
        prefs.emergencyMinutes = 15
        try expectEqual(prefs.emergencyMinutes, 15, "in range roundtrips")
    }

    // MARK: - Lists

    test("emergency apps roundtrip as codable list and dedupe by bundle ID") {
        let prefs = freshEmergencyPrefs()
        try expectEqual(prefs.emergencyApps, [], "default empty")
        prefs.addEmergencyApp(BlockedApp(bundleID: "com.apple.dt.Xcode", name: "Xcode"))
        prefs.addEmergencyApp(BlockedApp(bundleID: "com.apple.dt.Xcode", name: "Xcode Again"))
        try expectEqual(
            prefs.emergencyApps, [BlockedApp(bundleID: "com.apple.dt.Xcode", name: "Xcode")],
            "deduped by bundle ID"
        )
    }

    test("emergency domains sanitize, dedupe, and report what stuck") {
        let prefs = freshEmergencyPrefs()
        try expectEqual(prefs.emergencyDomains, [], "default empty")
        try expectEqual(
            prefs.addEmergencyDomain("https://www.Wikipedia.org/wiki/"), "www.wikipedia.org",
            "sanitized form is stored and reported"
        )
        try expectNil(prefs.addEmergencyDomain("   "), "whitespace-only dropped")
        try expectNil(prefs.addEmergencyDomain("www.wikipedia.org"), "duplicate dropped")
        try expectEqual(prefs.emergencyDomains, ["www.wikipedia.org"], "stored exactly once")
    }

    test("emergency lists never arm the shield or touch the other lists") {
        let prefs = freshEmergencyPrefs()
        prefs.addEmergencyApp(BlockedApp(bundleID: "com.apple.dt.Xcode", name: "Xcode"))
        prefs.addEmergencyDomain("wikipedia.org")
        try expect(!prefs.focusBlockEnabled, "the emergency mode arms itself, never the shield")
        try expectEqual(prefs.blockMode, .blocklist, "and never switches the block mode")
        try expectEqual(prefs.allowedApps, [], "allowlist untouched")
        try expectEqual(prefs.allowedDomains, [], "allowed domains untouched")
        try expectEqual(prefs.blockedApps, [], "blocklist untouched")
        try expectEqual(prefs.blockedDomains, [], "blocked domains untouched")
    }
}
