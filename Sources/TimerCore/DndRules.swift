import Foundation

public enum DndRules {
    /// Do-not-disturb follows the *session*, not the momentary activity:
    /// it stays on while a focus session is merely paused (user request,
    /// v10.1) and ends only on stop/finish. Pomodoro breaks — scheduled
    /// recovery, running or paused — keep it off, matching the block.
    public static func isActive(phase: TimerEngine.Phase, enabled: Bool) -> Bool {
        guard enabled else { return false }
        let kind: SessionKind
        switch phase {
        case .running(_, _, let activeKind), .paused(_, _, let activeKind):
            kind = activeKind
        case .idle, .finished:
            return false
        }
        switch kind {
        case .single:
            return true
        case .pomodoro(let pomPhase, _):
            return pomPhase == .focus
        }
    }
}
