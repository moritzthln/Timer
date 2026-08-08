import SwiftUI
import TimerCore

struct SetupView: View {
    @ObservedObject var engine: TimerEngine
    let preferences: Preferences

    @State private var minutesText = ""
    @State private var soundEnabled = true
    @FocusState private var inputFocused: Bool

    private static let presets = [5, 10, 15, 25, 45, 60]

    private var enteredMinutes: Int? {
        guard let value = Int(minutesText), value >= 1 else { return nil }
        return value
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField("25", text: $minutesText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .focused($inputFocused)
                    .onSubmit(startFromField)
                Text("min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Start", action: startFromField)
                    .keyboardShortcut(.defaultAction)
                    .disabled(enteredMinutes == nil)
            }
            HStack(spacing: 4) {
                ForEach(Self.presets, id: \.self) { minutes in
                    Button(String(minutes)) {
                        engine.start(minutes: minutes)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: 10, design: .monospaced))
                }
            }
            Divider()
            HStack {
                Button {
                    soundEnabled.toggle()
                    preferences.soundEnabled = soundEnabled
                } label: {
                    Image(systemName: soundEnabled ? "speaker.wave.2" : "speaker.slash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(soundEnabled ? "Ton aus" : "Ton an")
                Spacer()
                Text("⌘Q Beenden")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            minutesText = String(preferences.lastMinutes)
            soundEnabled = preferences.soundEnabled
            DispatchQueue.main.async { inputFocused = true }
        }
    }

    private func startFromField() {
        guard let minutes = enteredMinutes else { return }
        engine.start(minutes: minutes)
    }
}
