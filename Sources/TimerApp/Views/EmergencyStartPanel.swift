import SwiftUI
import TimerCore

/// v24: the small start sheet of the emergency mode. It lives inside the
/// popover instead of being a real NSWindow sheet — the popover is transient
/// and would take a sheet with it the moment it loses focus.
struct EmergencyStartPanel: View {
    @ObservedObject var emergency: EmergencyController
    let preferences: Preferences

    @State private var minutesText = ""
    @FocusState private var inputFocused: Bool

    /// The model clamps 1...60 anyway; the field only refuses what cannot be
    /// a duration at all, so Start is never dead for a typed-in value.
    private var enteredMinutes: Int? {
        guard let value = Int(minutesText), value >= 1 else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            minutesRow
            startButton
            captions
        }
        .onAppear {
            minutesText = String(emergency.suggestedMinutes)
            DispatchQueue.main.async { inputFocused = true }
        }
        // The popover is transient: closing it dismisses the panel like a
        // sheet, instead of greeting the user with it on the next open.
        .onDisappear { emergency.isConfiguring = false }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
            Text(tr("Notfall-Modus", "Emergency mode"))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                emergency.isConfiguring = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(tr("Zurück", "Back"))
        }
    }

    private var minutesRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TextField("25", text: $minutesText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: 56)
                .focused($inputFocused)
                .onSubmit(start)
                .onChange(of: minutesText) { newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(2))
                    if filtered != newValue { minutesText = filtered }
                }
            Text(tr("min · max. \(EmergencyMode.maximumMinutes)", "min · max \(EmergencyMode.maximumMinutes)"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var startButton: some View {
        Button(action: start) {
            Text(tr("Starten", "Start"))
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .keyboardShortcut(.defaultAction)
        .disabled(enteredMinutes == nil)
    }

    private var captions: some View {
        VStack(alignment: .leading, spacing: 3) {
            caption(tr("Nur deine Notfall-Apps sind erreichbar. Abbrechen erst nach 10 s Halten.", "Only your emergency apps stay reachable. Cancelling takes a 10 s hold."))
            if preferences.emergencyApps.isEmpty {
                caption(tr("Noch keine Notfall-Apps gewählt — dann wird alles außer Timer, Finder und Systemeinstellungen ausgeblendet.", "No emergency apps chosen yet — everything but Timer, Finder and System Settings will be hidden."))
            }
            caption(tr("Timer beenden hebt die Sperre auf; beim nächsten Start läuft sie weiter.", "Quitting Timer lifts the lock; it resumes on the next launch."))
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func start() {
        guard let minutes = enteredMinutes else { return }
        emergency.start(minutes: minutes)
    }
}
