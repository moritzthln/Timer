import SwiftUI
import TimerCore

struct TimerView: View {
    @ObservedObject var engine: TimerEngine
    let preferences: Preferences
    var onOpenSettings: () -> Void
    var onToggleFloating: () -> Void

    var body: some View {
        Group {
            switch engine.phase {
            case .idle:
                SetupView(
                    engine: engine, preferences: preferences,
                    onOpenSettings: onOpenSettings, onToggleFloating: onToggleFloating
                )
            case .running, .paused:
                RunningView(engine: engine)
            case .finished:
                FinishedView(engine: engine)
            }
        }
        .padding(12)
        .frame(width: 200)
    }
}
