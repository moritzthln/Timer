import Foundation

public struct PomodoroConfig: Equatable {
    public var focusMinutes: Int
    public var breakMinutes: Int
    public var longBreakMinutes: Int
    public var rounds: Int

    public init(focusMinutes: Int = 25, breakMinutes: Int = 5,
                longBreakMinutes: Int = 15, rounds: Int = 4) {
        self.focusMinutes = focusMinutes
        self.breakMinutes = breakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.rounds = rounds
    }

    public func duration(of phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .focus: return TimeInterval(focusMinutes * 60)
        case .shortBreak: return TimeInterval(breakMinutes * 60)
        case .longBreak: return TimeInterval(longBreakMinutes * 60)
        }
    }

    /// The kind that follows `kind` when its phase completes.
    /// `.single` maps to itself (callers never advance singles).
    public func next(after kind: SessionKind) -> SessionKind {
        guard case .pomodoro(let phase, let round) = kind else { return kind }
        switch phase {
        case .focus:
            return round >= rounds
                ? .pomodoro(phase: .longBreak, round: round)
                : .pomodoro(phase: .shortBreak, round: round)
        case .shortBreak:
            return .pomodoro(phase: .focus, round: round + 1)
        case .longBreak:
            return .pomodoro(phase: .focus, round: 1)
        }
    }
}
