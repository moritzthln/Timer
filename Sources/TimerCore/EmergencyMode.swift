import Foundation

/// v24: one bounded lockdown session — the Mac is reduced to the pre-chosen
/// emergency apps and websites until `endDate`. Independent of timers,
/// pomodoro, and the shield: it carries nothing but its own end date, which
/// is why it survives a relaunch as a single persisted value.
public struct EmergencySession: Equatable {
    public let endDate: Date

    public init(endDate: Date) {
        self.endDate = endDate
    }
}

/// The pure rules behind the emergency mode. The duration cap lives here —
/// not in the UI — so no code path can start a session longer than an hour.
public enum EmergencyMode {
    public static let minimumMinutes = 1
    public static let maximumMinutes = 60
    /// What the start sheet offers before the user ever changed it.
    public static let defaultMinutes = 25

    /// The only gate on the duration: every caller goes through `start`.
    public static func clamp(minutes: Int) -> Int {
        min(maximumMinutes, max(minimumMinutes, minutes))
    }

    public static func start(minutes: Int, now: Date = Date()) -> EmergencySession {
        EmergencySession(
            endDate: now.addingTimeInterval(TimeInterval(clamp(minutes: minutes) * 60))
        )
    }

    /// The end date itself already counts as over, so a session that just
    /// elapsed can never re-arm itself on the next read.
    public static func isActive(session: EmergencySession?, now: Date = Date()) -> Bool {
        guard let session else { return false }
        return session.endDate > now
    }

    /// Rounded up like `TimerEngine.remainingSeconds`, so the banner shows a
    /// full second for any part of one, and never a negative remainder.
    public static func remainingSeconds(session: EmergencySession?, now: Date = Date()) -> Int {
        guard let session else { return 0 }
        return max(0, Int(session.endDate.timeIntervalSince(now).rounded(.up)))
    }
}
