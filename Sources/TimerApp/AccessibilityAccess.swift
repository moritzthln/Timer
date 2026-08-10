import AppKit
import ApplicationServices

/// Accessibility bridge of the block. Apps in native macOS fullscreen ignore
/// `NSRunningApplication.hide()`; the only way to get them out without killing
/// anything is to flip their windows' `AXFullScreen` attribute — or, as a last
/// resort, to minimise them. Both need the Accessibility permission.
///
/// The permission is requested **lazily**: never at launch, only the first
/// time the block actually runs — and at most once per app run, so a denied
/// permission never turns into a prompt loop.
enum AccessibilityAccess {
    /// Live, never-prompting read — the status source for Settings → Rechte.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// "AXFullScreen": the attribute macOS uses for native fullscreen
    /// windows. It has no public constant, only this string.
    private static let fullScreenAttribute = "AXFullScreen" as CFString

    /// True once the macOS prompt was shown in this app run.
    private static var didPrompt = false

    /// How long an app gets to answer an AX request. The default is six
    /// seconds — and every one of them would be spent blocking the main
    /// thread, which since v25 asks several times a second. A hung app is
    /// exactly the kind that also refuses to hide, so waiting for it would
    /// freeze the Timer on the worst possible occasion.
    private static let messagingTimeout: Float = 0.25

    /// An app element that answers quickly or not at all.
    private static func element(pid: pid_t) -> AXUIElement {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        return application
    }

    /// Returns whether the app may drive other apps, prompting once if it
    /// may not. Already-trusted callers never see a prompt; a user who
    /// declines is asked at most once per app run (the loop then makes do
    /// with hiding and the keyboard shortcut).
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
    /// (the loop keeps trying its other techniques).
    @discardableResult
    static func exitFullscreen(pid: pid_t) -> Bool {
        let application = element(pid: pid)
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

    /// Minimises every window of the app into the Dock. The last resort of
    /// the block since v23.1: it needs no cover window, survives apps that
    /// refuse `hide()`, and the user gets the windows back from the Dock in
    /// exactly the state they were in.
    @discardableResult
    static func minimizeWindows(pid: pid_t) -> Bool {
        let application = element(pid: pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXWindowsAttribute as CFString, &value
        ) == .success, let windows = value as? [AXUIElement] else { return false }

        var changed = false
        for window in windows {
            let result = AXUIElementSetAttributeValue(
                window, kAXMinimizedAttribute as CFString, kCFBooleanTrue
            )
            if result == .success { changed = true }
        }
        return changed
    }

    /// True once the block warned about the missing permission in this run.
    private static var didWarn = false

    /// Says out loud what used to fail silently. Without this permission the
    /// block cannot touch a fullscreen app at all — neither the AX route nor
    /// the keyboard shortcut, which macOS also gates behind it — so `hide()`
    /// is all that is left, and apps in native fullscreen ignore that. The
    /// user then sees a block that does nothing, with no hint why (which is
    /// exactly what happened: an ad-hoc signed app loses the grant on every
    /// reinstall, and macOS keeps showing the stale entry as if it were on).
    ///
    /// Shown at most once per app run, and only when a block actually starts.
    static func warnIfMissing() {
        guard !isTrusted, !didWarn else { return }
        didWarn = true
        let alert = NSAlert()
        alert.messageText = "Timer fehlen die Bedienungshilfen"
        alert.informativeText = """
        Ohne dieses Recht kann der Block Apps im Vollbild weder beenden noch \
        ausblenden — er wirkt dann wirkungslos.

        Öffne Datenschutz & Sicherheit → Bedienungshilfen. Steht „Timer“ dort \
        schon: mit „−“ entfernen und mit „+“ neu hinzufügen \
        (/Applications/Timer.app). Nach jeder Neuinstallation ist das nötig, \
        solange die App nur ad-hoc signiert ist.
        """
        alert.addButton(withTitle: "Einstellungen öffnen")
        alert.addButton(withTitle: "Später")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { openSettings() }
    }

    /// Opens System Settings → Datenschutz & Sicherheit → Bedienungshilfen.
    static func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// True when any of the app's windows is in native fullscreen. A cheap
    /// read (no write, no prompt) that tells the loop whether the keyboard
    /// shortcut is warranted — sending it to a windowed app would toggle it
    /// *into* fullscreen.
    static func isAppFullscreen(pid: pid_t) -> Bool {
        let application = element(pid: pid)
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
