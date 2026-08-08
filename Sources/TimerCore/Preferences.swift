import Foundation

public final class Preferences {
    private let defaults: UserDefaults

    private enum Key {
        static let lastMinutes = "lastMinutes"
        static let soundEnabled = "soundEnabled"
        static let endDate = "persistedEndDate"
        static let total = "persistedTotal"
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

    public func persistRunning(endDate: Date, total: TimeInterval) {
        defaults.set(endDate.timeIntervalSince1970, forKey: Key.endDate)
        defaults.set(total, forKey: Key.total)
    }

    public func clearRunning() {
        defaults.removeObject(forKey: Key.endDate)
        defaults.removeObject(forKey: Key.total)
    }

    public var persistedRun: (endDate: Date, total: TimeInterval)? {
        guard let timestamp = defaults.object(forKey: Key.endDate) as? Double,
              let total = defaults.object(forKey: Key.total) as? Double else {
            return nil
        }
        return (Date(timeIntervalSince1970: timestamp), total)
    }
}
