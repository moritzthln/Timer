import Foundation

public struct MenuBarPresentation: Equatable {
    public let symbol: String?
    public let title: String

    public static func make(phase: TimerEngine.Phase, remainingSeconds: Int) -> MenuBarPresentation {
        let time = TimeFormatting.format(seconds: remainingSeconds)
        switch phase {
        case .idle:
            return MenuBarPresentation(symbol: "timer", title: "")
        case .running(_, _, let kind):
            switch kind {
            case .single:
                return MenuBarPresentation(symbol: nil, title: time)
            case .pomodoro(let pomPhase, _):
                let symbol = pomPhase == .focus ? nil : "cup.and.saucer.fill"
                return MenuBarPresentation(symbol: symbol, title: time)
            }
        case .paused:
            return MenuBarPresentation(symbol: "pause.fill", title: time)
        case .finished:
            return MenuBarPresentation(symbol: nil, title: "0:00")
        }
    }
}
