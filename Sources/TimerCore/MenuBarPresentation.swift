import Foundation

/// v8: "Standard" keeps the exact countdown, "Kompakt" shows rounded-up
/// whole minutes ("25m", "1h 5m").
public enum MenuBarTimeFormat: String, CaseIterable {
    case standard
    case compact
}

public struct MenuBarPresentation: Equatable {
    public let symbol: String?
    public let title: String

    /// Defaults preserve the pre-v8 behavior (standard format, time shown)
    /// and the pre-v24 one (no emergency session).
    public static func make(
        phase: TimerEngine.Phase, remainingSeconds: Int,
        format: MenuBarTimeFormat = .standard, showTime: Bool = true,
        emergencySeconds: Int? = nil
    ) -> MenuBarPresentation {
        let session = self.session(
            phase: phase, remainingSeconds: remainingSeconds, format: format, showTime: showTime
        )
        guard let emergencySeconds else { return session }
        // v24: one symbol at a time — the lock outranks every phase icon,
        // because the emergency is the stronger state. The time text belongs
        // to a live session; only an idle Timer lends its empty title to the
        // emergency countdown, and "Nur Symbol" keeps it empty either way.
        let title = session.title.isEmpty && showTime
            ? formatted(emergencySeconds, as: format)
            : session.title
        return MenuBarPresentation(symbol: "lock.fill", title: title)
    }

    private static func session(
        phase: TimerEngine.Phase, remainingSeconds: Int,
        format: MenuBarTimeFormat, showTime: Bool
    ) -> MenuBarPresentation {
        guard showTime else {
            return MenuBarPresentation(symbol: iconOnlySymbol(phase: phase), title: "")
        }
        switch phase {
        case .idle:
            return MenuBarPresentation(symbol: "timer", title: "")
        case .running(_, _, let kind):
            let time = formatted(remainingSeconds, as: format)
            switch kind {
            case .single:
                return MenuBarPresentation(symbol: nil, title: time)
            case .pomodoro(let pomPhase, _):
                let symbol = pomPhase == .focus ? nil : "cup.and.saucer.fill"
                return MenuBarPresentation(symbol: symbol, title: time)
            }
        case .paused:
            return MenuBarPresentation(
                symbol: "pause.fill", title: formatted(remainingSeconds, as: format)
            )
        case .finished:
            return MenuBarPresentation(symbol: nil, title: formatted(0, as: format))
        }
    }

    private static func formatted(_ seconds: Int, as format: MenuBarTimeFormat) -> String {
        switch format {
        case .standard: return TimeFormatting.format(seconds: seconds)
        case .compact: return TimeFormatting.compact(seconds: seconds)
        }
    }

    /// "Nur Symbol": with every title hidden, each phase still needs a
    /// distinguishable icon — single/focus runs show the timer symbol,
    /// finished a checkmark.
    private static func iconOnlySymbol(phase: TimerEngine.Phase) -> String {
        switch phase {
        case .idle:
            return "timer"
        case .running(_, _, let kind):
            if case .pomodoro(let pomPhase, _) = kind, pomPhase != .focus {
                return "cup.and.saucer.fill"
            }
            return "timer"
        case .paused:
            return "pause.fill"
        case .finished:
            return "checkmark.circle"
        }
    }
}
