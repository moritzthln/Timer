import SwiftUI
import TimerCore

extension Notification.Name {
    static let timerSettingsChanged = Notification.Name("timerSettingsChanged")
}

struct SettingsView: View {
    let preferences: Preferences

    @State private var presetTexts: [String] = []
    @State private var focusText = ""
    @State private var breakText = ""
    @State private var longBreakText = ""
    @State private var roundsText = ""
    @State private var volume = 1.0
    @State private var launchAtLogin = false
    @State private var floating = true
    @State private var loginHint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Presets (Minuten)") {
                HStack(spacing: 6) {
                    ForEach(0..<6, id: \.self) { index in
                        TextField("", text: presetBinding(index))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .frame(width: 44)
                            .onSubmit(commitPresets)
                    }
                }
            }

            section("Pomodoro") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Fokus (min)")
                        numberField($focusText, commit: commitPomodoro)
                    }
                    GridRow {
                        Text("Pause (min)")
                        numberField($breakText, commit: commitPomodoro)
                    }
                    GridRow {
                        Text("Lange Pause (min)")
                        numberField($longBreakText, commit: commitPomodoro)
                    }
                    GridRow {
                        Text("Runden bis lange Pause")
                        numberField($roundsText, commit: commitPomodoro)
                    }
                }
            }

            section("Alarm") {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.wave.2")
                        .foregroundStyle(.secondary)
                    Slider(value: $volume, in: 0...1)
                        .onChange(of: volume) { newValue in
                            preferences.alarmVolume = newValue
                        }
                    Button("Test") {
                        SoundPlayer.playCompletionChime(volume: preferences.alarmVolume)
                    }
                }
            }

            section("Allgemein") {
                Toggle("Beim Anmelden starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        guard newValue != LaunchAtLogin.isEnabled else { return }
                        do {
                            try LaunchAtLogin.setEnabled(newValue)
                            loginHint = nil
                        } catch {
                            launchAtLogin = LaunchAtLogin.isEnabled
                            loginHint = "macOS hat das abgelehnt. Manuell: Systemeinstellungen → Allgemein → Anmeldeobjekte → \"+\" → Timer.app."
                        }
                    }
                if let hint = loginHint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Floating Display", isOn: $floating)
                    .onChange(of: floating) { newValue in
                        preferences.floatingEnabled = newValue
                        NotificationCenter.default.post(name: .timerSettingsChanged, object: nil)
                    }
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear(perform: load)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func numberField(_ text: Binding<String>, commit: @escaping () -> Void) -> some View {
        TextField("", text: text)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: 60)
            .onSubmit(commit)
    }

    private func presetBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < presetTexts.count ? presetTexts[index] : "" },
            set: { newValue in
                if index < presetTexts.count {
                    presetTexts[index] = String(newValue.filter(\.isNumber).prefix(3))
                }
            }
        )
    }

    private func load() {
        presetTexts = preferences.presets.map(String.init)
        let config = preferences.pomodoroConfig
        focusText = String(config.focusMinutes)
        breakText = String(config.breakMinutes)
        longBreakText = String(config.longBreakMinutes)
        roundsText = String(config.rounds)
        volume = preferences.alarmVolume
        launchAtLogin = LaunchAtLogin.isEnabled
        floating = preferences.floatingEnabled
    }

    private func commitPresets() {
        let values = presetTexts.map { Int($0) ?? 0 }
        guard values.allSatisfy({ $0 >= 1 }) else {
            presetTexts = preferences.presets.map(String.init)
            return
        }
        preferences.presets = values
        presetTexts = preferences.presets.map(String.init)
    }

    private func commitPomodoro() {
        var config = preferences.pomodoroConfig
        if let focus = Int(focusText) { config.focusMinutes = focus }
        if let brk = Int(breakText) { config.breakMinutes = brk }
        if let long = Int(longBreakText) { config.longBreakMinutes = long }
        if let rounds = Int(roundsText) { config.rounds = rounds }
        preferences.pomodoroConfig = config
        let saved = preferences.pomodoroConfig
        focusText = String(saved.focusMinutes)
        breakText = String(saved.breakMinutes)
        longBreakText = String(saved.longBreakMinutes)
        roundsText = String(saved.rounds)
    }
}
