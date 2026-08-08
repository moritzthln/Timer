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
        prefs.persistRun(PersistedRun(
            endDate: current.addingTimeInterval(300), total: 1500, kind: .single, config: nil
        ))
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
        prefs.persistRun(PersistedRun(
            endDate: current.addingTimeInterval(-10), total: 1500, kind: .single, config: nil
        ))
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

    test("startPomodoro begins focus round 1 and persists config") {
        let prefs = freshEnginePrefs()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { start })
        let config = PomodoroConfig(focusMinutes: 25, breakMinutes: 5, longBreakMinutes: 15, rounds: 4)
        engine.startPomodoro(config: config)
        try expectEqual(
            engine.phase,
            .running(endDate: start.addingTimeInterval(1500), total: 1500,
                     kind: .pomodoro(phase: .focus, round: 1)),
            "phase"
        )
        try expectEqual(prefs.persistedRun?.config, config, "config persisted")
    }

    test("focus end advances seamlessly into break with one phase-change callback") {
        let prefs = freshEnginePrefs()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { current })
        var changes: [SessionKind] = []
        engine.onPhaseChange = { changes.append($0) }
        engine.startPomodoro(config: PomodoroConfig(focusMinutes: 1, breakMinutes: 1, longBreakMinutes: 2, rounds: 2))
        current = current.addingTimeInterval(61)
        engine.tick()
        try expectEqual(
            engine.phase,
            .running(endDate: Date(timeIntervalSince1970: 1_000_000 + 120), total: 60,
                     kind: .pomodoro(phase: .shortBreak, round: 1)),
            "break starts at the focus boundary, not at tick time"
        )
        try expectEqual(changes, [.pomodoro(phase: .shortBreak, round: 1)], "one callback")
    }

    test("catch-up fast-forwards multiple missed phases with one callback") {
        let prefs = freshEnginePrefs()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { current })
        var changes: [SessionKind] = []
        engine.onPhaseChange = { changes.append($0) }
        // 1-min focus, 1-min break, 2-min long break, 2 rounds → cycle: F1 B1 F2 LB
        engine.startPomodoro(config: PomodoroConfig(focusMinutes: 1, breakMinutes: 1, longBreakMinutes: 2, rounds: 2))
        // Sleep through focus1 (0-60), break1 (60-120), focus2 (120-180); wake inside long break (180-300)
        current = current.addingTimeInterval(200)
        engine.tick()
        try expectEqual(
            engine.phase,
            .running(endDate: Date(timeIntervalSince1970: 1_000_000 + 300), total: 120,
                     kind: .pomodoro(phase: .longBreak, round: 2)),
            "landed in the phase containing now"
        )
        try expectEqual(changes.count, 1, "single catch-up callback")
    }

    test("skip jumps to next phase starting now without callback") {
        let prefs = freshEnginePrefs()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { current })
        var changes: [SessionKind] = []
        engine.onPhaseChange = { changes.append($0) }
        engine.startPomodoro(config: PomodoroConfig(focusMinutes: 25, breakMinutes: 5, longBreakMinutes: 15, rounds: 4))
        current = current.addingTimeInterval(600)
        engine.skip()
        try expectEqual(
            engine.phase,
            .running(endDate: current.addingTimeInterval(300), total: 300,
                     kind: .pomodoro(phase: .shortBreak, round: 1)),
            "break starts at skip time"
        )
        try expectEqual(changes.count, 0, "user-initiated skip is silent")
    }

    test("skip while paused resumes running in next phase") {
        let prefs = freshEnginePrefs()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { current })
        engine.startPomodoro(config: PomodoroConfig(focusMinutes: 25, breakMinutes: 5, longBreakMinutes: 15, rounds: 4))
        engine.pause()
        engine.skip()
        guard case .running(_, _, let kind) = engine.phase else {
            throw AssertionError(description: "expected running, got \(engine.phase)")
        }
        try expectEqual(kind, .pomodoro(phase: .shortBreak, round: 1), "advanced")
    }

    test("skip on single timer does nothing") {
        let prefs = freshEnginePrefs()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { start })
        engine.start(minutes: 10)
        let before = engine.phase
        engine.skip()
        try expectEqual(engine.phase, before, "unchanged")
    }

    test("pomodoro restore past boundary catches up without callbacks") {
        let prefs = freshEnginePrefs()
        let current = Date(timeIntervalSince1970: 1_000_000)
        let config = PomodoroConfig(focusMinutes: 1, breakMinutes: 1, longBreakMinutes: 2, rounds: 2)
        // Persist a focus phase that ended 130s ago: F ended at -130; B(-130..-70), F2(-70..-10), LB(-10..+110)
        prefs.persistRun(PersistedRun(
            endDate: current.addingTimeInterval(-130), total: 60,
            kind: .pomodoro(phase: .focus, round: 1), config: config
        ))
        var changes = 0
        let engine = TimerEngine(preferences: prefs, now: { current })
        engine.onPhaseChange = { _ in changes += 1 }
        try expectEqual(
            engine.phase,
            .running(endDate: current.addingTimeInterval(110), total: 120,
                     kind: .pomodoro(phase: .longBreak, round: 2)),
            "restored into the current phase"
        )
        try expectEqual(changes, 0, "restore never fires callbacks (wired after init anyway)")
    }

    test("focus segments: start→pause credits elapsed time") {
        let prefs = freshEnginePrefs()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { current })
        var segments: [(Date, Date)] = []
        engine.onFocusSegmentEnded = { segments.append($0) }
        engine.start(minutes: 25)
        current = current.addingTimeInterval(300)
        engine.pause()
        try expectEqual(segments.count, 1, "one segment")
        try expectEqual(segments[0].1.timeIntervalSince(segments[0].0), 300, accuracy: 0.001, "5 min")
    }

    test("focus segments: resume→stop credits the second part only") {
        let prefs = freshEnginePrefs()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { current })
        var total = 0.0
        engine.onFocusSegmentEnded = { total += $0.1.timeIntervalSince($0.0) }
        engine.start(minutes: 25)
        current = current.addingTimeInterval(300)
        engine.pause()
        current = current.addingTimeInterval(1000)
        engine.resume()
        current = current.addingTimeInterval(120)
        engine.stop()
        try expectEqual(total, 420, accuracy: 0.001, "300 + 120")
    }

    test("focus segments: single finish credits the full duration, clamped") {
        let prefs = freshEnginePrefs()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { current })
        var segments: [(Date, Date)] = []
        engine.onFocusSegmentEnded = { segments.append($0) }
        engine.start(minutes: 1)
        current = current.addingTimeInterval(500) // tick arrives long after the end
        engine.tick()
        try expectEqual(segments.count, 1, "one segment")
        try expectEqual(segments[0].1.timeIntervalSince(segments[0].0), 60, accuracy: 0.001, "clamped to 60")
    }

    test("focus segments: pomodoro focus credits, break does not") {
        let prefs = freshEnginePrefs()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { current })
        var total = 0.0
        engine.onFocusSegmentEnded = { total += $0.1.timeIntervalSince($0.0) }
        engine.startPomodoro(config: PomodoroConfig(focusMinutes: 1, breakMinutes: 1, longBreakMinutes: 2, rounds: 2))
        current = current.addingTimeInterval(61)
        engine.tick() // focus → break: credit 60
        try expectEqual(total, 60, accuracy: 0.001, "focus credited")
        current = current.addingTimeInterval(61)
        engine.tick() // break → focus: no credit
        try expectEqual(total, 60, accuracy: 0.001, "break not credited")
    }

    test("focus segments: skip mid-focus credits elapsed") {
        let prefs = freshEnginePrefs()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimerEngine(preferences: prefs, now: { current })
        var total = 0.0
        engine.onFocusSegmentEnded = { total += $0.1.timeIntervalSince($0.0) }
        engine.startPomodoro(config: PomodoroConfig(focusMinutes: 25, breakMinutes: 5, longBreakMinutes: 15, rounds: 4))
        current = current.addingTimeInterval(400)
        engine.skip()
        try expectEqual(total, 400, accuracy: 0.001, "elapsed focus credited on skip")
    }
}
