import AppKit
import ApplicationServices

/// v18 Accessibility bridge — the second rung of the block escalation ladder.
/// Apps in native macOS fullscreen ignore `NSRunningApplication.hide()`; the
/// only way to get them out without killing anything is to flip their
/// windows' `AXFullScreen` attribute, which needs the Accessibility
/// permission.
///
/// The permission is requested **lazily**: never at launch, only the first
/// time the ladder actually reaches step 2 — and at most once per app run,
/// so a denied permission never turns into a prompt loop.
enum AccessibilityAccess {
    /// Live, never-prompting read — the status source for Settings → Rechte.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// "AXFullScreen": the attribute macOS uses for native fullscreen
    /// windows. It has no public constant, only this string.
    private static let fullScreenAttribute = "AXFullScreen" as CFString

    /// True once the macOS prompt was shown in this app run.
    private static var didPrompt = false

    /// Returns whether the app may drive other apps, prompting once if it
    /// may not. Already-trusted callers never see a prompt; a user who
    /// declines is asked at most once per app run (the ladder then simply
    /// skips step 2 and covers the app instead).
    static func requestIfNeeded() -> Bool {
        if isTrusted { return true }
        guard !didPrompt else { return false }
        didPrompt = true
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true,
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Pulls every fullscreen window of the given process out of fullscreen.
    /// Returns whether at least one window was changed; any missing
    /// permission, unscriptable app, or attribute error simply yields false
    /// (the caller escalates to the cover overlay).
    @discardableResult
    static func exitFullscreen(pid: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXWindowsAttribute as CFString, &value
        ) == .success, let windows = value as? [AXUIElement] else { return false }

        var changed = false
        for window in windows where isFullscreen(window) {
            let result = AXUIElementSetAttributeValue(
                window, fullScreenAttribute, kCFBooleanFalse
            )
            if result == .success { changed = true }
        }
        return changed
    }

    /// Opens System Settings → Datenschutz & Sicherheit → Bedienungshilfen.
    static func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// True when any of the app's windows is in native fullscreen. A cheap
    /// read (no write, no prompt) that lets the block skip the rungs which
    /// cannot work there — hide() is refused for fullscreen apps and Catalyst
    /// or Electron windows reject the AXFullScreen write.
    static func isAppFullscreen(pid: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXWindowsAttribute as CFString, &value
        ) == .success, let windows = value as? [AXUIElement] else { return false }
        return windows.contains(where: isFullscreen)
    }

    private static func isFullscreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window, fullScreenAttribute, &value
        ) == .success else { return false }
        return (value as? Bool) ?? false
    }
}
