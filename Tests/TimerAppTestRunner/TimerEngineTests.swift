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
        guard case .running(let end, let total, _) = engine.phase else {
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

    test("pause freezes remaining and clears persistence") {
        let prefs = freshEnginePrefs()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { current })
        engine.start(minutes: 25)
        current = current.addingTimeInterval(100)
        engine.pause()
        try expectEqual(engine.phase, .paused(remaining: 1400, total: 1500, kind: .single), "phase")
        try expectNil(prefs.persistedRun, "persistence cleared while paused")
        current = current.addingTimeInterval(500)
        try expectEqual(engine.remainingSeconds, 1400, "paused time must not advance")
    }

    test("resume schedules new end date from now") {
        let prefs = freshEnginePrefs()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { current })
        engine.start(minutes: 25)
        current = current.addingTimeInterval(100)
        engine.pause()
        current = current.addingTimeInterval(999)
        engine.resume()
        guard case .running(let end, let total, _) = engine.phase else {
            throw AssertionError(description: "expected .running, got \(engine.phase)")
        }
        try expectEqual(total, 1500, "total survives pause")
        try expectEqual(end, current.addingTimeInterval(1400), "new endDate")
        try expectEqual(prefs.persistedRun?.endDate, end, "persisted endDate")
    }

    test("tick before end stays running without finish") {
        let prefs = freshEnginePrefs()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { current })
        var finishCount = 0
        engine.onFinish = { finishCount += 1 }
        engine.start(minutes: 1)
        current = current.addingTimeInterval(59)
        engine.tick()
        try expectEqual(finishCount, 0, "no finish yet")
        guard case .running = engine.phase else {
            throw AssertionError(description: "expected .running, got \(engine.phase)")
        }
    }

    test("tick at end finishes once and clears persistence") {
        let prefs = freshEnginePrefs()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { current })
        var finishCount = 0
        engine.onFinish = { finishCount += 1 }
        engine.start(minutes: 1)
        current = current.addingTimeInterval(60)
        engine.tick()
        try expectEqual(engine.phase, .finished, "phase")
        try expectEqual(finishCount, 1, "finish fired once")
        try expectNil(prefs.persistedRun, "persistence cleared")
        engine.tick()
        try expectEqual(finishCount, 1, "finished tick must not re-fire onFinish")
    }

    test("restore with future end date resumes running") {
        let prefs = freshEnginePrefs()
        let current = Date(timeIntervalSince1970: 1_000_000)
        prefs.persistRunning(endDate: current.addingTimeInterval(300), total: 1500)
        let engine = TimerEngine(preferences: prefs, now: { current })
        try expectEqual(
            engine.phase,
            .running(endDate: current.addingTimeInterval(300), total: 1500, kind: .single),
            "phase restored"
        )
        try expectEqual(engine.remainingSeconds, 300, "remaining")
    }

    test("restore with past end date shows finished and clears") {
        let prefs = freshEnginePrefs()
        let current = Date(timeIntervalSince1970: 1_000_000)
        prefs.persistRunning(endDate: current.addingTimeInterval(-10), total: 1500)
        let engine = TimerEngine(preferences: prefs, now: { current })
        try expectEqual(engine.phase, .finished, "phase")
        try expectNil(prefs.persistedRun, "stale persistence cleared")
    }

    test("dismissFinished returns to idle") {
        let prefs = freshEnginePrefs()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { current })
        engine.start(minutes: 1)
        current = current.addingTimeInterval(60)
        engine.tick()
        engine.dismissFinished()
        try expectEqual(engine.phase, .idle, "phase")
    }

    test("progress advances with elapsed fraction") {
        let prefs = freshEnginePrefs()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { current })
        try expectEqual(engine.progress, 0, accuracy: 0.0001, "idle")
        engine.start(minutes: 10)
        try expectEqual(engine.progress, 0, accuracy: 0.001, "at start")
        current = current.addingTimeInterval(300)
        try expectEqual(engine.progress, 0.5, accuracy: 0.001, "halfway")
        engine.pause()
        try expectEqual(engine.progress, 0.5, accuracy: 0.001, "paused keeps progress")
    }
}
