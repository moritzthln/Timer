import Carbon.HIToolbox
import AppKit
import TimerCore

/// Registers system-wide hotkeys via Carbon (no permissions needed).
final class HotkeyManager {
    enum Action: UInt32 {
        case openPopover = 1
        case quickStart = 2
        case extend = 3
    }

    var onAction: ((Action) -> Void)?

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false

    func apply(popover: HotkeyCombo?, quickStart: HotkeyCombo?, extend: HotkeyCombo?) {
        installHandlerIfNeeded()
        unregisterAll()
        if let popover { register(popover, as: .openPopover) }
        if let quickStart { register(quickStart, as: .quickStart) }
        if let extend { register(extend, as: .extend) }
    }

    private func register(_ combo: HotkeyCombo, as action: Action) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x54494D52) /* 'TIMR' */, id: action.rawValue)
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode), UInt32(combo.carbonModifiers),
            hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr, let ref {
            refs[action.rawValue] = ref
        }
    }

    private func unregisterAll() {
        for (_, ref) in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
                )
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                if let action = Action(rawValue: hotKeyID.id) {
                    DispatchQueue.main.async { manager.onAction?(action) }
                }
                return noErr
            },
            1, &eventType, selfPointer, nil
        )
        handlerInstalled = true
    }
}

enum HotkeyDisplay {
    private static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋",
    ]

    static func string(for combo: HotkeyCombo) -> String {
        var parts = ""
        if combo.carbonModifiers & controlKey != 0 { parts += "⌃" }
        if combo.carbonModifiers & optionKey != 0 { parts += "⌥" }
        if combo.carbonModifiers & shiftKey != 0 { parts += "⇧" }
        if combo.carbonModifiers & cmdKey != 0 { parts += "⌘" }
        parts += keyNames[combo.keyCode] ?? "Key\(combo.keyCode)"
        return parts
    }

    /// NSEvent modifier flags → Carbon modifiers. Returns nil if no
    /// command/control/option modifier is present (plain keys not allowed).
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int? {
        var carbon = 0
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        guard carbon & (cmdKey | controlKey | optionKey) != 0 else { return nil }
        return carbon
    }
}
