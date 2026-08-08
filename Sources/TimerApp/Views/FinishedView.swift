import SwiftUI
import TimerCore

struct FinishedView: View {
    @ObservedObject var engine: TimerEngine

    var body: some View {
        VStack(spacing: 10) {
            Text("0:00")
                .font(.system(size: 38, design: .monospaced).weight(.medium))
            Text("Fertig")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Neuer Timer") { engine.dismissFinished() }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }
}
