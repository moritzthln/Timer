import Foundation
import TimerCore

private func freshPrefs() -> Preferences {
    let suite = "PreferencesTests"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return Preferences(defaults: defaults)
}

func runPreferencesTests() {
    test("lastMinutes defaults to 25 and roundtrips") {
        let prefs = freshPrefs()
        try expectEqual(prefs.lastMinutes, 25)
        prefs.lastMinutes = 45
        try expectEqual(prefs.lastMinutes, 45)
    }

    test("soundEnabled defaults to true and roundtrips") {
        let prefs = freshPrefs()
        try expect(prefs.soundEnabled, "default must be true")
        prefs.soundEnabled = false
        try expect(!prefs.soundEnabled, "must persist false")
    }

    test("single run roundtrips") {
        let prefs = freshPrefs()
        try expectNil(prefs.persistedRun, "starts empty")
        let end = Date(timeIntervalSince1970: 2_000_000)
        let run = PersistedRun(endDate: end, total: 1500, kind: .single, config: nil)
        prefs.persistRun(run)
        try expectEqual(prefs.persistedRun, run, "roundtrip")
        prefs.clearRunning()
        try expectNil(prefs.persistedRun, "cleared")
    }

    test("pomodoro run roundtrips with config") {
        let prefs = freshPrefs()
        let end = Date(timeIntervalSince1970: 2_000_000)
        let config = PomodoroConfig(focusMinutes: 20, breakMinutes: 4, longBreakMinutes: 12, rounds: 3)
        let run = PersistedRun(
            endDate: end, total: 1200,
            kind: .pomodoro(phase: .shortBreak, round: 2), config: config
        )
        prefs.persistRun(run)
        try expectEqual(prefs.persistedRun, run, "roundtrip incl. kind and config")
    }

    test("presets default and sanitize") {
        let prefs = freshPrefs()
        try expectEqual(prefs.presets, [5, 10, 15, 25, 45, 60], "default")
        prefs.presets = [1, 999, 30, 30, 30, 30]
        try expectEqual(prefs.presets, [1, 720, 30, 30, 30, 30], "clamped to 1...720")
        prefs.presets = [7]
        try expectEqual(prefs.presets, [1, 720, 30, 30, 30, 30], "wrong count rejected, keeps previous")
    }

    test("pomodoro config prefs default and clamp") {
        let prefs = freshPrefs()
        try expectEqual(prefs.pomodoroConfig, PomodoroConfig(), "defaults 25/5/15/4")
        prefs.pomodoroConfig = PomodoroConfig(focusMinutes: 0, breakMinutes: 9999, longBreakMinutes: 10, rounds: 99)
        try expectEqual(prefs.pomodoroConfig, PomodoroConfig(focusMinutes: 1, breakMinutes: 720, longBreakMinutes: 10, rounds: 12), "clamped")
    }

    test("alarm volume, floating, lastMode roundtrip") {
        let prefs = freshPrefs()
        try expectEqual(prefs.alarmVolume, 1.0, accuracy: 0.0001, "volume default")
        prefs.alarmVolume = 0.4
        try expectEqual(prefs.alarmVolume, 0.4, accuracy: 0.0001, "volume roundtrip")
        try expect(prefs.floatingEnabled, "floating default on")
        prefs.floatingEnabled = false
        try expect(!prefs.floatingEnabled, "floating off")
        try expectEqual(prefs.lastMode, "timer", "mode default")
        prefs.lastMode = "pomodoro"
        try expectEqual(prefs.lastMode, "pomodoro", "mode roundtrip")
    }
}
