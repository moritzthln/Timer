import SwiftUI
import TimerCore

struct FinishedView: View {
    @ObservedObject var engine: TimerEngine

    var body: some View {
        VStack(spacing: 10) {
            Text("0:00")
                .font(.system(size: 38, design: .monospaced).weight(.medium))
            Text(tr("Fertig", "Done"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(tr("Neuer Timer", "New timer")) { engine.dismissFinished() }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }
}
