import AppKit
import TimerCore

/// v18: runs the `BlockEscalation` ladder for one app and owns everything the
/// ladder touches — the v16 popup, the hidden-apps restore record, and (from
/// the next rung on) the Accessibility un-fullscreen.
///
/// Every rung verifies instead of assuming: `hide()` reports success even for
/// fullscreen apps that stay right where they are, so the enforcer re-reads
/// `isHidden` a moment later and escalates if the app is still visible.
final class AppBlockEnforcer {
    /// How long macOS gets to actually hide an app before the ladder judges
    /// the attempt. Short enough to feel immediate, long enough for the
    /// hide/space animation to have started.
    private static let verifyDelay = 0.25

    private let popup: BlockOverlayController
    private let remainingSeconds: () -> Int
    private var hiddenApps = HiddenAppsRecord()

    /// Whether the block is still active — delayed ladder steps drop out
    /// when the session ended, paused, or the shield went off meanwhile.
    var isActive: () -> Bool = { true }

    init(popup: BlockOverlayController, remainingSeconds: @escaping () -> Int) {
        self.popup = popup
        self.remainingSeconds = remainingSeconds
    }

    /// Entry point for every block event (sweep, launch, activation, poll).
    func enforce(app: NSRunningApplication, name: String) {
        run(step: .start, app: app, name: name)
    }

    /// Unhides every app this enforcer hid and clears the record. Apps the
    /// user hid manually were never recorded and stay untouched.
    func restoreHiddenApps() {
        let ids = hiddenApps.drain()
        guard !ids.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, ids.contains(id) {
                _ = app.unhide()
            }
        }
    }

    // MARK: - Ladder

    private func run(step: BlockEscalation.Step, app: NSRunningApplication, name: String) {
        let visible = isVisible(app)
        let action = BlockEscalation.next(
            step: step, appVisible: visible,
            accessibilityGranted: accessibilityGranted(atStep: step, visible: visible)
        )
        switch action {
        case .hide:
            hideAndRecord(app)
            announce(name)
            verify(after: action, app: app, name: name)
        case .unfullscreenThenHide:
            AccessibilityAccess.exitFullscreen(pid: app.processIdentifier)
            hideAndRecord(app)
            verify(after: action, app: app, name: name)
        case .overlay:
            // The cover overlay lands in the next step of v18; until then the
            // popup stays the last word, exactly as in v16.
            announce(name)
        case .done:
            break
        }
    }

    /// Re-runs the ladder once macOS had its moment, unless the block ended
    /// in the meantime.
    private func verify(
        after action: BlockEscalation.Action, app: NSRunningApplication, name: String
    ) {
        let next = BlockEscalation.Step.after(action)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.verifyDelay) { [weak self] in
            guard let self, self.isActive() else { return }
            self.run(step: next, app: app, name: name)
        }
    }

    /// The permission is only ever asked for where the ladder would need it —
    /// at step 2, on a still-visible app. Every other rung's decision is
    /// independent of it, so no check (and no prompt) happens there.
    private func accessibilityGranted(
        atStep step: BlockEscalation.Step, visible: Bool
    ) -> Bool {
        guard visible, step == .hideTried else { return false }
        return AccessibilityAccess.requestIfNeeded()
    }

    private func isVisible(_ app: NSRunningApplication) -> Bool {
        !app.isTerminated && !app.isHidden
    }

    /// Gentle intervention: hide and remember what *we* hid, so restore never
    /// touches anything this app did not hide itself. A refused hide is not
    /// an error here — the ladder escalates on the verification instead.
    private func hideAndRecord(_ app: NSRunningApplication) {
        guard !app.isHidden, app.hide(), let id = app.bundleIdentifier else { return }
        hiddenApps.add(id)
    }

    private func announce(_ name: String) {
        popup.show(target: name, remainingSeconds: remainingSeconds())
    }
}
