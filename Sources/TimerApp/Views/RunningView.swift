import SwiftUI
import TimerCore

struct RunningView: View {
    @ObservedObject var engine: TimerEngine

    var body: some View {
        VStack(spacing: 6) {
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
                Button("Stopp") { engine.stop() }
            }
            .controlSize(.small)
        }
    }
}
