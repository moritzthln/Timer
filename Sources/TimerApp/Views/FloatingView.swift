import SwiftUI
import TimerCore

struct FloatingView: View {
    @ObservedObject var engine: TimerEngine
    @State private var hovering = false

    private var pomodoroLabel: String? {
        guard case .pomodoro(let phase, let round)? = engine.currentKind else { return nil }
        switch phase {
        case .focus: return "Fokus \(round)"
        case .shortBreak: return "Pause \(round)"
        case .longBreak: return "Lange Pause"
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 4) {
                if let label = pomodoroLabel {
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text(TimeFormatting.format(seconds: engine.remainingSeconds))
                    .font(.system(size: 22, design: .monospaced).weight(.medium))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.quaternary)
                        Rectangle().fill(.primary)
                            .frame(width: geo.size.width * engine.progress)
                    }
                }
                .frame(height: 2)
                .clipShape(Capsule())
            }
            .opacity(hovering ? 0.25 : 1)

            if hovering {
                HStack(spacing: 6) {
                    Button(engine.isPaused ? "Weiter" : "Pause") {
                        if engine.isPaused {
                            engine.resume()
                        } else {
                            engine.pause()
                        }
                    }
                    Button("+5") { engine.extend(minutes: 5) }
                    Button("Stopp") { engine.stop() }
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 140)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, .dark)
        .onHover { hovering = $0 }
    }
}
