import SwiftUI
import TimerCore

struct TimerView: View {
    @ObservedObject var engine: TimerEngine
    let preferences: Preferences
    let stats: StatsStore
    var onOpenSettings: () -> Void
    var onToggleFloating: () -> Void
    var onOpenStats: () -> Void

    var body: some View {
        Group {
            switch engine.phase {
            case .idle:
                SetupView(
                    engine: engine, preferences: preferences, stats: stats,
                    onOpenSettings: onOpenSettings, onToggleFloating: onToggleFloating,
                    onOpenStats: onOpenStats
                )
            case .running, .paused:
                RunningView(engine: engine)
            case .finished:
                FinishedView(engine: engine)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 240)
    }
}
