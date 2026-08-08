import Foundation
import TimerCore

private func freshEnginePrefs() -> Preferences {
    let suite = "TimerEngineTests"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return Preferences(defaults: defaults)
}

func runTimerEngineTests() {
    test("start enters running and persists") {
        let prefs = freshEnginePrefs()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { start })
        engine.start(minutes: 25)
        guard case .running(let end, let total) = engine.phase else {
            throw AssertionError(description: "expected .running, got \(engine.phase)")
        }
        try expectEqual(total, 1500, "total")
        try expectEqual(end, start.addingTimeInterval(1500), "endDate")
        try expectEqual(engine.remainingSeconds, 1500, "remaining")
        try expectEqual(prefs.lastMinutes, 25, "lastMinutes")
        try expectEqual(prefs.persistedRun?.total, 1500, "persisted total")
    }

    test("start clamps minutes to 1...720") {
        let prefs = freshEnginePrefs()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { start })
        engine.start(minutes: 0)
        try expectEqual(engine.remainingSeconds, 60, "clamped up to 1 min")
        engine.start(minutes: 9999)
        try expectEqual(engine.remainingSeconds, 720 * 60, "clamped down to 720 min")
    }

    test("remainingSeconds tracks wall clock") {
        let prefs = freshEnginePrefs()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { current })
        engine.start(minutes: 25)
        current = current.addingTimeInterval(10)
        try expectEqual(engine.remainingSeconds, 1490, "after 10s")
    }

    test("stop returns to idle and clears persistence") {
        let prefs = freshEnginePrefs()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { start })
        engine.start(minutes: 25)
        engine.stop()
        try expectEqual(engine.phase, .idle, "phase")
        try expectNil(prefs.persistedRun, "persistence")
    }
}
