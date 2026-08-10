import AppKit
import SwiftUI
import TimerCore

struct SetupView: View {
    @ObservedObject var engine: TimerEngine
    let preferences: Preferences
    var onOpenSettings: () -> Void
    var onToggleFloating: () -> Void
    var onOpenStats: () -> Void

    @State private var minutesText = ""
    @State private var soundEnabled = true
    @State private var floatingOn = true
    @State private var focusBlockOn = false
    @State private var blockMode = BlockMode.blocklist
    @State private var presets: [Int] = [5, 15, 25, 45]
    @FocusState private var inputFocused: Bool

    /// What the field shows and what Start uses. `minutesText` is only filled
    /// by `onAppear`, and SwiftUI does not reliably re-run that when the idle
    /// view comes back after "Fertig" — the field then sat empty with a dead
    /// Start button (user report). Falling back to the stored value unless the
    /// user is actively editing makes the display independent of lifecycle
    /// events, while an empty field during typing stays empty.
    private var displayedMinutes: String {
        if minutesText.isEmpty, !inputFocused {
            return String(preferences.lastMinutes)
        }
        return minutesText
    }

    private var minutesBinding: Binding<String> {
        Binding(get: { displayedMinutes }, set: { minutesText = $0 })
    }

    private var enteredMinutes: Int? {
        guard let value = Int(displayedMinutes), value >= 1 else { return nil }
        return value
    }

    var body: some View {
        VStack(spacing: 12) {
            heroInput
            presetRow
            pomodoroChip
            startButton
            footer
                .padding(.top, 2)
        }
        .onChange(of: engine.phase) { phase in
            // Coming back from a finished or stopped session: re-seed the
            // field from the stored value and take focus again.
            guard case .idle = phase else { return }
            minutesText = String(preferences.lastMinutes)
            DispatchQueue.main.async { inputFocused = true }
        }
        .onAppear {
            minutesText = String(preferences.lastMinutes)
            soundEnabled = preferences.soundEnabled
            floatingOn = preferences.floatingEnabled
            focusBlockOn = preferences.focusBlockEnabled
            blockMode = preferences.blockMode
            presets = preferences.presets
            DispatchQueue.main.async { inputFocused = true }
        }
    }

    // MARK: - Hero input

    private var heroInput: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            TextField("25", text: minutesBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 34, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .fixedSize()
                .focused($inputFocused)
                .onSubmit(startFromField)
                .onChange(of: minutesText) { newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(3))
                    if filtered != newValue { minutesText = filtered }
                }
            Text("min")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Preset chips

    private var presetRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(presets.enumerated()), id: \.offset) { _, minutes in
                presetChip(minutes)
            }
        }
    }

    private func presetChip(_ minutes: Int) -> some View {
        let isActive = enteredMinutes == minutes
        return Button {
            engine.start(minutes: minutes)
        } label: {
            Text(String(minutes))
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06))
                )
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pomodoro chip

    /// Spec names the modern glyph with `repeat` as fallback; the probe keeps
    /// the chip rendering on macOS 13, where the modern name does not exist.
    private var pomodoroSymbol: String {
        let modern = "arrow.trianglehead.2.clockwise"
        return NSImage(systemSymbolName: modern, accessibilityDescription: nil) != nil
            ? modern : "repeat"
    }

    private var pomodoroChip: some View {
        let config = preferences.pomodoroConfig
        return Button {
            engine.startPomodoro(config: preferences.pomodoroConfig)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: pomodoroSymbol)
                    .font(.system(size: 10))
                Text("Pomodoro · \(config.focusMinutes) / \(config.breakMinutes) · \(config.rounds) Runden")
                    .font(.system(size: 11))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: - Start

    private var startButton: some View {
        Button(action: startFromField) {
            Text("Start")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(enteredMinutes == nil)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            shieldButton
            if focusBlockOn { modeControl }

            Spacer()

            Button(action: onOpenStats) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Statistik")

            moreMenu
        }
    }

    /// While the mode control is visible the label collapses to the icon —
    /// the 240 pt popover cannot fit label, both segments, and the footer
    /// icons in one row.
    private var shieldButton: some View {
        Button {
            focusBlockOn.toggle()
            preferences.focusBlockEnabled = focusBlockOn
        } label: {
            HStack(spacing: 4) {
                Image(systemName: focusBlockOn ? "shield.fill" : "shield")
                    .font(.system(size: 11))
                if !focusBlockOn {
                    Text("Fokus-Block")
                        .font(.system(size: 11))
                }
            }
            .foregroundStyle(focusBlockOn ? Color.green : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(focusBlockOn ? "Fokus-Block aus" : "Fokus-Block an")
    }

    /// v15.1: a single toggle chip showing the active mode fully readable —
    /// two labeled segments truncated at 240 pt (user report). Clicking
    /// switches to the other mode; the tooltip explains both.
    private var modeControl: some View {
        Button {
            let next: BlockMode = blockMode == .blocklist ? .allowlist : .blocklist
            blockMode = next
            preferences.blockMode = next
        } label: {
            HStack(spacing: 3) {
                Image(systemName: blockMode == .blocklist ? "nosign" : "checkmark.circle")
                    .font(.system(size: 8, weight: .semibold))
                Text(blockMode == .blocklist ? "Blockieren" : "Nur Erlaubte")
                    .font(.system(size: 9, weight: .medium))
                    .fixedSize()
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.accentColor.opacity(0.2))
            )
            .foregroundStyle(Color.accentColor)
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(
            blockMode == .blocklist
                ? "Modus: Blockieren — blendet markierte Apps aus, Tabs markierter Websites warten im Hintergrund. Klicken wechselt zu \"Nur Erlaubte\"."
                : "Modus: Nur Erlaubte — blendet alle Apps außer den erlaubten aus, nur Tabs erlaubter Websites bleiben vorn (leere Liste blockt nichts). Klicken wechselt zu \"Blockieren\"."
        )
    }

    private var moreMenu: some View {
        Menu {
            Toggle("Ton", isOn: Binding(
                get: { soundEnabled },
                set: { newValue in
                    soundEnabled = newValue
                    preferences.soundEnabled = newValue
                }
            ))
            Toggle("Floating Display", isOn: Binding(
                get: { floatingOn },
                set: { newValue in
                    floatingOn = newValue
                    onToggleFloating()
                }
            ))
            Divider()
            Button("Einstellungen…", action: onOpenSettings)
            Divider()
            Button("Timer beenden…") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Mehr")
    }

    private func startFromField() {
        guard let minutes = enteredMinutes else { return }
        engine.start(minutes: minutes)
    }
}
