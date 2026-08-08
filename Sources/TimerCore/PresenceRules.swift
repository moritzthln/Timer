import Foundation

public enum PresenceRules {
    public static func isPresent(
        lastInputAge: TimeInterval, thresholdSeconds: TimeInterval,
        screenLocked: Bool, asleep: Bool, paused: Bool
    ) -> Bool {
        !screenLocked && !asleep && !paused && lastInputAge <= thresholdSeconds
    }
}
