import Foundation

public enum FocusBlockRules {
    /// Blocking runs only during running focus work: single timers and
    /// pomodoro focus phases. Breaks and pauses are free time.
    public static func isActive(phase: TimerEngine.Phase, enabled: Bool) -> Bool {
        guard enabled, case .running(_, _, let kind) = phase else { return false }
        switch kind {
        case .single:
            return true
        case .pomodoro(let pomPhase, _):
            return pomPhase == .focus
        }
    }

    /// True if `host` is the entry itself or a subdomain of it.
    public static func domainMatches(host: String, entry: String) -> Bool {
        let normalizedHost = host.lowercased()
        let normalizedEntry = entry.lowercased()
        return normalizedHost == normalizedEntry
            || normalizedHost.hasSuffix("." + normalizedEntry)
    }
}
