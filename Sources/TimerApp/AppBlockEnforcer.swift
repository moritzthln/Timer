import AppKit
import TimerCore

/// v18: runs the `BlockEscalation` ladder for one app and owns everything the
/// ladder touches — the v16 popup, the hidden-apps restore record, the
/// Accessibility un-fullscreen, the v21 Space escape, and the cover overlay.
///
/// Every rung verifies instead of assuming: `hide()` reports success even for
/// fullscreen apps that stay right where they are, so the enforcer re-reads
/// `isHidden` a moment later and escalates if the app is still visible.
final class AppBlockEnforcer {
    /// How long macOS gets to actually hide an app before the ladder judges
    /// the attempt. Short enough to feel immediate, long enough for the
    /// hide/space animation to have started.
    private static let verifyDelay = 0.25
    /// The same for the Space escape, whose switch is an animation.
    private static let escapeVerifyDelay = 0.6
    /// v21: one Space escape per app per 3 s. Deliberately short — a longer
    /// window would hand the user a comfortable stay inside the distraction.
    private static let escapeInterval = 3.0
    /// How long after an escape the poll must keep its hands off the cover:
    /// right after activating, *we* are the frontmost app, which would
    /// otherwise read as "something harmless came forward" and undo the
    /// escape before its retry-hide even ran.
    private static let escapeCoverGrace = 1.5
    /// How long the cover of a diagnostic run stays up after its report.
    private static let probeCoverLinger = 1.2

    private let popup: BlockOverlayController
    private let cover: BlockCoverController
    private let remainingSeconds: () -> Int
    private var hiddenApps = HiddenAppsRecord()
    /// When each app was last pulled out of its Space (throttle memory).
    private var lastEscape: [String: Date] = [:]
    /// When the most recent escape of any app happened (cover grace).
    private var lastEscapeAt: Date?
    /// Non-nil while a diagnostic run is in flight: who is being probed, the
    /// rungs it took, and where to report. Keyed by pid because a real
    /// session may keep enforcing other apps at the same time — their rungs
    /// must not end up in the diagnostic's log.
    private var probeReport: ((ProbeOutcome) -> Void)?
    private var probeTarget: pid_t?
    private var probeActions: [BlockEscalation.Action] = []

    /// Whether the block is still active — delayed ladder steps drop out
    /// when the session ended, paused, or the shield went off meanwhile.
    var isActive: () -> Bool = { true }

    init(
        popup: BlockOverlayController,
        cover: BlockCoverController,
        remainingSeconds: @escaping () -> Int
    ) {
        self.popup = popup
        self.cover = cover
        self.remainingSeconds = remainingSeconds
    }

    /// What a v21 diagnostic run ended up doing. The wording is the one the
    /// "Rechte" tab prints, so the mapping stays next to the ladder that
    /// produces it.
    enum ProbeOutcome: String {
        case noAction = "kein Eingriff nötig"
        case hidden = "versteckt"
        case unfullscreened = "aus Vollbild geholt"
        case spaceSwitched = "Space gewechselt"
        case covered = "überdeckt"
    }

    /// Entry point for every block event (sweep, launch, activation, poll).
    func enforce(app: NSRunningApplication, name: String) {
        run(step: .start, app: app, name: name)
    }

    /// v21 "Vollbild-Block testen": the very same ladder, run once against
    /// one app, ignoring both block lists and the session state — the point
    /// is to see the real chain, not a simulation. Delayed rungs normally
    /// stop at `isActive()`; while probing they keep going, the escape
    /// ignores its throttle, and the cover is taken down afterwards because
    /// a diagnostic must not leave a black screen behind.
    func probe(
        app: NSRunningApplication, name: String,
        report: @escaping (ProbeOutcome) -> Void
    ) {
        guard probeReport == nil else { return }
        probeReport = report
        probeTarget = app.processIdentifier
        probeActions = []
        run(step: .start, app: app, name: name)
    }

    /// Undoes every intervention: the cover comes down and everything the
    /// block hid is unhidden. Runs on block deactivation and on app quit.
    func restore() {
        lastEscape = [:]
        lastEscapeAt = nil
        cover.hide()
        restoreHiddenApps()
    }

    /// Takes the cover down because the covered app is no longer frontmost —
    /// unless a Space escape just put it there (see `escapeCoverGrace`).
    func releaseCover() {
        if let lastEscapeAt, Date().timeIntervalSince(lastEscapeAt) < Self.escapeCoverGrace {
            return
        }
        cover.hide()
    }

    /// Unhides every app this enforcer hid and clears the record. Apps the
    /// user hid manually were never recorded and stay untouched.
    private func restoreHiddenApps() {
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
        let probing = isProbing(app)
        let action = BlockEscalation.next(
            step: step, appVisible: visible, appFrontmost: isFrontmost(app),
            accessibilityGranted: accessibilityGranted(atStep: step, visible: visible),
            escapeAllowed: probing || escapeAllowed(app)
        )
        if probing { probeActions.append(action) }
        switch action {
        case .hide:
            hideAndRecord(app)
            announce(name)
            verify(after: action, app: app, name: name)
        case .unfullscreenThenHide:
            AccessibilityAccess.exitFullscreen(pid: app.processIdentifier)
            hideAndRecord(app)
            verify(after: action, app: app, name: name)
        case .spaceEscape:
            escape(app: app, name: name)
            // The ladder retries the hide right after the switch: an app that
            // no longer holds the screen usually accepts it, and then the
            // cover comes down on its own (`.done`).
            verify(after: action, app: app, name: name)
        case .overlay:
            showCover(target: name, bundleID: app.bundleIdentifier, escaped: false)
        case .done:
            // The app is out of sight — so is any cover that belonged to it.
            cover.hide(ifCovering: app.bundleIdentifier)
        }
        // Both are terminal rungs: nothing verifies after them, so a probe
        // has seen everything it is going to see.
        if probing, action == .overlay || action == .done {
            finishProbe(app: app)
        }
    }

    /// v21 rung 3: the cover goes up on the Timer's own Space first, then the
    /// app activates and makes it key. That is the whole trick — macOS moves
    /// the user to wherever the activated app's key window lives, which is
    /// anywhere but the blocked app's fullscreen Space.
    private func escape(app: NSRunningApplication, name: String) {
        showCover(target: name, bundleID: app.bundleIdentifier, escaped: true)
        cover.escape()
        let now = Date()
        lastEscape[Self.escapeKey(app)] = now
        lastEscapeAt = now
    }

    private func showCover(target name: String, bundleID: String?, escaped: Bool) {
        cover.show(
            target: name, bundleID: bundleID,
            remainingSeconds: remainingSeconds(), escaped: escaped
        )
    }

    /// Re-runs the ladder once macOS had its moment, unless the block ended
    /// in the meantime. The escape gets a longer moment than the hides: its
    /// Space switch is an animation, and the retry-hide should land after it
    /// rather than into it.
    private func verify(
        after action: BlockEscalation.Action, app: NSRunningApplication, name: String
    ) {
        let next = BlockEscalation.Step.after(action)
        let delay = action == .spaceEscape ? Self.escapeVerifyDelay : Self.verifyDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isActive() || self.isProbing(app) else { return }
            self.run(step: next, app: app, name: name)
        }
    }

    // MARK: - Diagnostics

    /// Whether this very app is the one under diagnosis.
    private func isProbing(_ app: NSRunningApplication) -> Bool {
        probeReport != nil && probeTarget == app.processIdentifier
    }

    /// Reports the run and clears the stage again.
    private func finishProbe(app: NSRunningApplication) {
        guard let report = probeReport else { return }
        let outcome = Self.probeOutcome(actions: probeActions, visible: isVisible(app))
        probeReport = nil
        probeTarget = nil
        probeActions = []
        report(outcome)
        // Unless a real session owns the cover by now, it comes down after a
        // moment on screen — long enough to be seen, short enough to not
        // strand the user behind a black rectangle.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.probeCoverLinger) { [weak self] in
            guard let self, !self.isActive() else { return }
            self.cover.hide()
        }
    }

    /// The strongest thing that actually happened wins: an app the ladder
    /// never had to touch reports nothing, an escape outranks the hides that
    /// came before it, and a still-visible app means the cover is all there
    /// was.
    private static func probeOutcome(
        actions: [BlockEscalation.Action], visible: Bool
    ) -> ProbeOutcome {
        if actions.first == .done { return .noAction }
        if actions.contains(.spaceEscape) { return .spaceSwitched }
        guard !visible else { return .covered }
        return actions.contains(.unfullscreenThenHide) ? .unfullscreened : .hidden
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

    /// The escape only makes sense while the app still owns the screen; once
    /// the user left on his own, a Space switch would be the intrusion.
    private func isFrontmost(_ app: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    /// The 3 s throttle. Between two escapes the ladder keeps trying to hide
    /// the app silently and falls back to the cover, so a user who ⌘-Tabs
    /// straight back is not thrown around the Spaces twice per second.
    private func escapeAllowed(_ app: NSRunningApplication) -> Bool {
        guard let last = lastEscape[Self.escapeKey(app)] else { return true }
        return Date().timeIntervalSince(last) >= Self.escapeInterval
    }

    /// Bundle id where there is one; unbundled helpers fall back to their pid.
    private static func escapeKey(_ app: NSRunningApplication) -> String {
        app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
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
