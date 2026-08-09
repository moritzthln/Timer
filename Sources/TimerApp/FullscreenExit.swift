import AppKit
import CoreGraphics

/// Leaving another app's fullscreen, the way that still works on macOS 14+.
///
/// `NSApp.activate(ignoringOtherApps:)` (the v21 escape) is deprecated since
/// macOS 14 and is routinely ignored under cooperative activation, so the
/// Space never switched on the user's macOS 26 machine. Synthetic key events
/// go through the *target* app's own menu handling instead, which is why they
/// also work for Catalyst/Electron windows that reject `AXFullScreen` writes.
///
/// Both helpers need the Accessibility permission (event posting is gated on
/// it); without it they are no-ops and the ladder falls through to the cover.
enum FullscreenExit {
    private static let fKeyCode: CGKeyCode = 3        // kVK_ANSI_F
    private static let leftArrowKeyCode: CGKeyCode = 123 // kVK_LeftArrow

    /// Sends ⌃⌘F — the system shortcut for "exit fullscreen" — to whatever is
    /// frontmost. Returns false when events cannot be posted at all.
    @discardableResult
    static func sendExitFullscreen() -> Bool {
        post(keyCode: fKeyCode, flags: [.maskCommand, .maskControl])
    }

    /// Sends ⌃← ("move one space left") as a fallback for apps whose
    /// fullscreen does not answer to ⌃⌘F (some games, some custom windows).
    @discardableResult
    static func sendSpaceLeft() -> Bool {
        post(keyCode: leftArrowKeyCode, flags: [.maskControl])
    }

    private static func post(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
