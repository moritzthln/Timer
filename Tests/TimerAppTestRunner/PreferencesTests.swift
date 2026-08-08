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

    test("persistedRun roundtrips and clears") {
        let prefs = freshPrefs()
        try expectNil(prefs.persistedRun, "starts empty")
        let end = Date(timeIntervalSince1970: 2_000_000)
        prefs.persistRunning(endDate: end, total: 1500)
        try expectEqual(prefs.persistedRun?.endDate, end, "endDate")
        try expectEqual(prefs.persistedRun?.total, 1500, "total")
        prefs.clearRunning()
        try expectNil(prefs.persistedRun, "cleared")
    }
}
