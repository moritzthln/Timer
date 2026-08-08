import SwiftUI
import TimerCore

struct RunningView: View {
    @ObservedObject var engine: TimerEngine

    private var pomodoroLabel: String? {
        guard case .pomodoro(let phase, let round)? = engine.currentKind else { return nil }
        switch phase {
        case .focus: return "Fokus · Runde \(round)"
        case .shortBreak: return "Pause · Runde \(round)"
        case .longBreak: return "Lange Pause"
        }
    }

    private var isPomodoro: Bool {
        if case .pomodoro? = engine.currentKind { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 6) {
            if let label = pomodoroLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(TimeFormatting.format(seconds: engine.remainingSeconds))
                .font(.system(size: 28, design: .monospaced).weight(.medium))
            if let end = engine.endDate {
                Text("endet \(end, format: .dateTime.hour().minute())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("pausiert")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.quaternary)
                    Rectangle().fill(.primary)
                        .frame(width: geo.size.width * engine.progress)
                }
            }
            .frame(height: 2)
            .clipShape(Capsule())
            HStack(spacing: 6) {
                Button(engine.isPaused ? "Weiter" : "Pause") {
                    if engine.isPaused {
                        engine.resume()
                    } else {
                        engine.pause()
                    }
                }
                if isPomodoro {
                    Button("Skip") { engine.skip() }
                }
                Button("Stopp") { engine.stop() }
            }
            .controlSize(.small)
        }
    }
}
