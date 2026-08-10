import SwiftUI
import TimerCore

struct TimerView: View {
    @ObservedObject var engine: TimerEngine
    /// v24: drives the emergency banner and the start panel.
    @ObservedObject var emergency: EmergencyController
    let preferences: Preferences
    var onOpenSettings: () -> Void
    var onToggleFloating: () -> Void
    var onOpenStats: () -> Void

    var body: some View {
        Group {
            if emergency.isConfiguring {
                EmergencyStartPanel(emergency: emergency, preferences: preferences)
            } else {
                VStack(spacing: 12) {
                    // Above every phase, not only the idle view: an emergency
                    // session coexists with a running timer or pomodoro, and
                    // its controls have to stay reachable underneath.
                    if emergency.isActive {
                        EmergencyBannerView(emergency: emergency)
                    }
                    phaseContent
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 240)
    }

    @ViewBuilder private var phaseContent: some View {
        switch engine.phase {
        case .idle:
            SetupView(
                engine: engine, preferences: preferences, emergency: emergency,
                onOpenSettings: onOpenSettings, onToggleFloating: onToggleFloating,
                onOpenStats: onOpenStats
            )
        case .running, .paused:
            RunningView(engine: engine)
        case .finished:
            FinishedView(engine: engine)
        }
    }
}
