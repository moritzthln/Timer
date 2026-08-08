import SwiftUI
import TimerCore

struct SetupView: View {
    @ObservedObject var engine: TimerEngine
    let preferences: Preferences
    var onOpenSettings: () -> Void
    var onToggleFloating: () -> Void

    @State private var minutesText = ""
    @State private var soundEnabled = true
    @State private var floatingOn = true
    @State private var mode = "timer"
    @State private var presets: [Int] = [5, 10, 15, 25, 45, 60]
    @FocusState private var inputFocused: Bool

    private var enteredMinutes: Int? {
        guard let value = Int(minutesText), value >= 1 else { return nil }
        return value
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $mode) {
                Text("Timer").tag("timer")
                Text("Pomodoro").tag("pomodoro")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: mode) { newValue in
                preferences.lastMode = newValue
                if newValue == "timer" {
                    DispatchQueue.main.async { inputFocused = true }
                }
            }

            if mode == "timer" {
                timerSetup
            } else {
                pomodoroSetup
            }

            Divider()
            footer
        }
        .onAppear {
            minutesText = String(preferences.lastMinutes)
            soundEnabled = preferences.soundEnabled
            floatingOn = preferences.floatingEnabled
            presets = preferences.presets
            mode = preferences.lastMode
            if mode == "timer" {
                DispatchQueue.main.async { inputFocused = true }
            }
        }
    }

    private var timerSetup: some View {
        Group {
            HStack(spacing: 6) {
                TextField("25", text: $minutesText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .focused($inputFocused)
                    .onSubmit(startFromField)
                    .onChange(of: minutesText) { newValue in
                        let filtered = String(newValue.filter(\.isNumber).prefix(3))
                        if filtered != newValue { minutesText = filtered }
                    }
                Text("min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Start", action: startFromField)
                    .keyboardShortcut(.defaultAction)
                    .disabled(enteredMinutes == nil)
            }
            HStack(spacing: 4) {
                ForEach(presets, id: \.self) { minutes in
                    Button(String(minutes)) {
                        engine.start(minutes: minutes)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: 10, design: .monospaced))
                }
            }
        }
    }

    private var pomodoroSetup: some View {
        let config = preferences.pomodoroConfig
        return Group {
            Text("\(config.focusMinutes) min Fokus · \(config.breakMinutes) min Pause · \(config.rounds) Runden")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Pomodoro starten") {
                engine.startPomodoro(config: preferences.pomodoroConfig)
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                soundEnabled.toggle()
                preferences.soundEnabled = soundEnabled
            } label: {
                Image(systemName: soundEnabled ? "speaker.wave.2" : "speaker.slash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(soundEnabled ? "Ton aus" : "Ton an")

            Button {
                floatingOn.toggle()
                onToggleFloating()
            } label: {
                Image(systemName: "macwindow.on.rectangle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(floatingOn ? .primary : .secondary)
            .help(floatingOn ? "Floating Display aus" : "Floating Display an")

            Button(action: onOpenSettings) {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Einstellungen")

            Spacer()
            Text("⌘Q")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private func startFromField() {
        guard let minutes = enteredMinutes else { return }
        engine.start(minutes: minutes)
    }
}
