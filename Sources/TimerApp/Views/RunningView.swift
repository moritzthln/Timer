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
        VStack(spacing: 10) {
            // The dedication sits above everything, in full weight: it is the
            // answer to "what am I doing", which the time alone never gives.
            // One line, cut off rather than wrapped — the popover is 240 pt.
            if !engine.label.isEmpty {
                Text(engine.label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(engine.label)
            }
            if let label = pomodoroLabel {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(TimeFormatting.format(seconds: engine.remainingSeconds))
                .font(.system(size: 38, design: .monospaced).weight(.medium))
            statusLine
            progressBar
            // v9: same icon vocabulary as the floating overlay — four text
            // pills next to each other looked bad at 240 pt.
            HStack(spacing: 8) {
                Button {
                    if engine.isPaused {
                        engine.resume()
                    } else {
                        engine.pause()
                    }
                } label: {
                    Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                }
                .help(engine.isPaused ? "Weiter" : "Pause")
                Button("+5") { engine.extend(minutes: 5) }
                    .help("+5 Minuten")
                if isPomodoro {
                    Button {
                        engine.skip()
                    } label: {
                        Image(systemName: "forward.end.fill")
                    }
                    .help("Phase überspringen")
                }
                Button {
                    engine.stop()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .help("Stopp")
            }
            .buttonStyle(PillButtonStyle())
        }
    }

    private var statusLine: some View {
        Group {
            if let end = engine.endDate {
                Text("endet \(end, format: .dateTime.hour().minute())")
            } else {
                Text("pausiert")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(.quaternary)
                Rectangle().fill(.primary)
                    .frame(width: geo.size.width * engine.progress)
            }
        }
        .frame(height: 3)
        .clipShape(Capsule())
    }
}
