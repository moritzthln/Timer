import SwiftUI
import AppKit
import TimerCore

/// Click → "Taste drücken…" → next combo (with ⌘/⌃/⌥) is captured.
/// Esc cancels. The clear button removes the hotkey.
struct HotkeyRecorderField: View {
    let combo: HotkeyCombo?
    let onChange: (HotkeyCombo?) -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggleRecording) {
                Text(recording ? "Taste drücken…" : label)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minWidth: 70)
            }
            if combo != nil && !recording {
                Button {
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        combo.map(HotkeyDisplay.string(for:)) ?? "—"
    }

    private func toggleRecording() {
        recording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc cancels
                stopRecording()
                return nil
            }
            guard let modifiers = HotkeyDisplay.carbonModifiers(from: event.modifierFlags) else {
                return nil // swallow plain keys while recording
            }
            let newCombo = HotkeyCombo(keyCode: Int(event.keyCode), carbonModifiers: modifiers)
            stopRecording()
            onChange(newCombo)
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
