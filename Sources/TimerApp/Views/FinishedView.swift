import SwiftUI
import TimerCore

struct FinishedView: View {
    @ObservedObject var engine: TimerEngine

    var body: some View {
        VStack(spacing: 8) {
            Text("0:00")
                .font(.system(size: 28, design: .monospaced).weight(.medium))
            Text("Fertig")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Neuer Timer") { engine.dismissFinished() }
                .keyboardShortcut(.defaultAction)
        }
    }
}
