import Foundation

public struct PersistedRun: Equatable {
    public var endDate: Date
    public var total: TimeInterval
    public var kind: SessionKind
    public var config: PomodoroConfig?

    public init(endDate: Date, total: TimeInterval, kind: SessionKind, config: PomodoroConfig?) {
        self.endDate = endDate
        self.total = total
        self.kind = kind
        self.config = config
    }
}

public struct BlockedApp: Codable, Equatable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public struct HotkeyCombo: Codable, Equatable {
    public let keyCode: Int
    public let carbonModifiers: Int

    public init(keyCode: Int, carbonModifiers: Int) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }
}

public final class Preferences {
    private let defaults: UserDefaults

    private enum Key {
        static let lastMinutes = "lastMinutes"
        static let soundEnabled = "soundEnabled"
        static let endDate = "persistedEndDate"
        static let total = "persistedTotal"
        static let kindPhase = "persistedKindPhase"
        static let kindRound = "persistedKindRound"
        static let cfgFocus = "persistedCfgFocus"
        static let cfgBreak = "persistedCfgBreak"
        static let cfgLongBreak = "persistedCfgLongBreak"
        static let cfgRounds = "persistedCfgRounds"
        static let presets = "presets"
        static let pomFocus = "pomFocus"
        static let pomBreak = "pomBreak"
        static let pomLongBreak = "pomLongBreak"
        static let pomRounds = "pomRounds"
        static let alarmVolume = "alarmVolume"
        static let floatingEnabled = "floatingEnabled"
        static let lastMode = "lastMode"
        static let blockedApps = "blockedApps"
        static let blockedDomains = "blockedDomains"
        static let focusBlockEnabled = "focusBlockEnabled"
        static let hotkeyPopover = "hotkeyPopover"
        static let hotkeyQuickStart = "hotkeyQuickStart"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var lastMinutes: Int {
        get {
            let value = defaults.integer(forKey: Key.lastMinutes)
            return value == 0 ? 25 : value
        }
        set { defaults.set(newValue, forKey: Key.lastMinutes) }
    }

    public var soundEnabled: Bool {
        get { defaults.object(forKey: Key.soundEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.soundEnabled) }
    }

    // MARK: - Run persistence

    public func persistRun(_ run: PersistedRun) {
        defaults.set(run.endDate.timeIntervalSince1970, forKey: Key.endDate)
        defaults.set(run.total, forKey: Key.total)
        switch run.kind {
        case .single:
            defaults.set("single", forKey: Key.kindPhase)
            defaults.removeObject(forKey: Key.kindRound)
        case .pomodoro(let phase, let round):
            let name: String
            switch phase {
            case .focus: name = "focus"
            case .shortBreak: name = "shortBreak"
            case .longBreak: name = "longBreak"
            }
            defaults.set(name, forKey: Key.kindPhase)
            defaults.set(round, forKey: Key.kindRound)
        }
        if let config = run.config {
            defaults.set(config.focusMinutes, forKey: Key.cfgFocus)
            defaults.set(config.breakMinutes, forKey: Key.cfgBreak)
            defaults.set(config.longBreakMinutes, forKey: Key.cfgLongBreak)
            defaults.set(config.rounds, forKey: Key.cfgRounds)
        }
    }

    public func clearRunning() {
        for key in [Key.endDate, Key.total, Key.kindPhase, Key.kindRound,
                    Key.cfgFocus, Key.cfgBreak, Key.cfgLongBreak, Key.cfgRounds] {
            defaults.removeObject(forKey: key)
        }
    }

    public var persistedRun: PersistedRun? {
        guard let timestamp = defaults.object(forKey: Key.endDate) as? Double,
              let total = defaults.object(forKey: Key.total) as? Double else {
            return nil
        }
        let kind: SessionKind
        var config: PomodoroConfig?
        switch defaults.string(forKey: Key.kindPhase) {
        case "focus", "shortBreak", "longBreak":
            let phase: PomodoroPhase
            switch defaults.string(forKey: Key.kindPhase)! {
            case "focus": phase = .focus
            case "shortBreak": phase = .shortBreak
            default: phase = .longBreak
            }
            let round = max(1, defaults.integer(forKey: Key.kindRound))
            kind = .pomodoro(phase: phase, round: round)
            config = PomodoroConfig(
                focusMinutes: defaults.integer(forKey: Key.cfgFocus),
                breakMinutes: defaults.integer(forKey: Key.cfgBreak),
                longBreakMinutes: defaults.integer(forKey: Key.cfgLongBreak),
                rounds: defaults.integer(forKey: Key.cfgRounds)
            )
        default:
            kind = .single
        }
        return PersistedRun(
            endDate: Date(timeIntervalSince1970: timestamp),
            total: total, kind: kind, config: config
        )
    }

    // MARK: - Settings

    private static func clampMinutes(_ value: Int) -> Int { min(720, max(1, value)) }

    public var presets: [Int] {
        get {
            guard let stored = defaults.array(forKey: Key.presets) as? [Int],
                  stored.count == 6 else {
                return [5, 10, 15, 25, 45, 60]
            }
            return stored.map(Self.clampMinutes)
        }
        set {
            guard newValue.count == 6 else { return }
            defaults.set(newValue.map(Self.clampMinutes), forKey: Key.presets)
        }
    }

    public var pomodoroConfig: PomodoroConfig {
        get {
            guard defaults.object(forKey: Key.pomFocus) != nil else { return PomodoroConfig() }
            return PomodoroConfig(
                focusMinutes: Self.clampMinutes(defaults.integer(forKey: Key.pomFocus)),
                breakMinutes: Self.clampMinutes(defaults.integer(forKey: Key.pomBreak)),
                longBreakMinutes: Self.clampMinutes(defaults.integer(forKey: Key.pomLongBreak)),
                rounds: min(12, max(1, defaults.integer(forKey: Key.pomRounds)))
            )
        }
        set {
            defaults.set(Self.clampMinutes(newValue.focusMinutes), forKey: Key.pomFocus)
            defaults.set(Self.clampMinutes(newValue.breakMinutes), forKey: Key.pomBreak)
            defaults.set(Self.clampMinutes(newValue.longBreakMinutes), forKey: Key.pomLongBreak)
            defaults.set(min(12, max(1, newValue.rounds)), forKey: Key.pomRounds)
        }
    }

    public var alarmVolume: Double {
        get { defaults.object(forKey: Key.alarmVolume) as? Double ?? 1.0 }
        set { defaults.set(min(1, max(0, newValue)), forKey: Key.alarmVolume) }
    }

    public var floatingEnabled: Bool {
        get { defaults.object(forKey: Key.floatingEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.floatingEnabled) }
    }

    public var lastMode: String {
        get { defaults.string(forKey: Key.lastMode) ?? "timer" }
        set { defaults.set(newValue, forKey: Key.lastMode) }
    }

    // MARK: - Focus block

    public var blockedApps: [BlockedApp] {
        get {
            guard let data = defaults.data(forKey: Key.blockedApps),
                  let apps = try? JSONDecoder().decode([BlockedApp].self, from: data) else {
                return []
            }
            return apps
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.blockedApps)
        }
    }

    public var blockedDomains: [String] {
        get { defaults.stringArray(forKey: Key.blockedDomains) ?? [] }
        set {
            let sanitized = newValue.compactMap(Self.sanitizeDomain)
            defaults.set(sanitized, forKey: Key.blockedDomains)
        }
    }

    /// "https://www.Foo.com/bar" → "www.foo.com"; whitespace-only → nil.
    public static func sanitizeDomain(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }
        for prefix in ["https://", "http://"] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }
        return value.isEmpty ? nil : value
    }

    public var focusBlockEnabled: Bool {
        get { defaults.object(forKey: Key.focusBlockEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.focusBlockEnabled) }
    }

    // MARK: - Hotkeys

    private func hotkey(forKey key: String) -> HotkeyCombo? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyCombo.self, from: data)
    }

    private func setHotkey(_ combo: HotkeyCombo?, forKey key: String) {
        if let combo {
            defaults.set(try? JSONEncoder().encode(combo), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    public var hotkeyPopover: HotkeyCombo? {
        get { hotkey(forKey: Key.hotkeyPopover) }
        set { setHotkey(newValue, forKey: Key.hotkeyPopover) }
    }

    public var hotkeyQuickStart: HotkeyCombo? {
        get { hotkey(forKey: Key.hotkeyQuickStart) }
        set { setHotkey(newValue, forKey: Key.hotkeyQuickStart) }
    }
}
