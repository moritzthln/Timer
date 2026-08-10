import AppKit
import TimerCore

/// v25: keeps one blocked app out of sight. Where v18–v21 climbed a ladder —
/// one technique per rung, one verification, then out of ideas — this insists:
/// a 0.2 s loop repeats every applicable technique (`BlockAttempt`) until the
/// app is actually gone, and `FocusBlockController`'s poll re-arms it for as
/// long as it is not. Nothing is destroyed; the app is hidden, minimised, or
/// pulled out of its fullscreen Space, and everything the enforcer hid is
/// unhidden again when the block ends.
///
/// v25 also drops the "Fokus läuft · noch MM:SS" popup: it announced what the
/// user could see anyway and got in the way of the block being unnoticeable.
final class AppBlockEnforcer {
    /// Between two attempts. Short enough that a hide landing on the second
    /// try still feels instant, long enough for macOS to have acted on the
    /// first.
    private static let interval = 0.2
    /// One burst, ~6 s. The poll re-arms a still-visible app right after, so
    /// this is a breather, not a surrender.
    private static let attempts = 30
    /// The diagnostic gets a shorter budget — it has to report something.
    private static let probeAttempts = 15
    /// One exit-fullscreen shortcut per app per 0.7 s: macOS's fullscreen-exit
    /// animation runs about half a second, and a shortcut landing inside it
    /// would put the app straight back in.
    private static let keyEventInterval = 0.7

    private var hiddenApps = HiddenAppsRecord()
    /// Apps with a loop in flight, so the 1 s poll never stacks a second one
    /// on top of a burst that is still running.
    private var running: Set<pid_t> = []
    /// When each app last received a keyboard shortcut (the throttle memory).
    private var lastKeyEvent: [pid_t: Date] = [:]

    /// Non-nil while a diagnostic run is in flight: who is being probed, what
    /// fired, and where to report. Keyed by pid because a real session may
    /// keep enforcing other apps at the same time.
    private var probeReport: ((ProbeOutcome) -> Void)?
    private var probeTarget: pid_t?
    private var probeFired: BlockPlan?

    /// Whether the block is still active — a loop drops out as soon as the
    /// session ended, paused, or the shield went off.
    var isActive: () -> Bool = { true }

    /// What a diagnostic run ended up doing. The wording is what the "Rechte"
    /// tab prints, so it stays next to the loop that produces it.
    enum ProbeOutcome: String {
        case noAction = "kein Eingriff nötig"
        case hidden = "versteckt"
        case unfullscreened = "aus Vollbild geholt"
        case spaceSwitched = "Space gewechselt"
        case minimized = "minimiert"
        case failed = "ließ sich nicht ausblenden"
    }

    /// Entry point for every block event (sweep, launch, activation, poll).
    /// Starting a loop for an app that already has one is a no-op — it is
    /// already insisting.
    func enforce(app: NSRunningApplication, name: String) {
        let pid = app.processIdentifier
        guard !running.contains(pid) else { return }
        guard isVisible(app) else { return }
        running.insert(pid)
        insist(app: app, attempt: 0)
    }

    /// "Vollbild-Block testen" in the Rechte tab: the very same loop against
    /// one app, ignoring both block lists and the session state — the point is
    /// to see the real mechanism, not a simulation.
    func probe(
        app: NSRunningApplication, name: String,
        report: @escaping (ProbeOutcome) -> Void
    ) {
        guard probeReport == nil else { return }
        probeReport = report
        probeTarget = app.processIdentifier
        probeFired = BlockPlan()
        guard !running.contains(app.processIdentifier) else {
            finishProbe(app: app)
            return
        }
        running.insert(app.processIdentifier)
        insist(app: app, attempt: 0)
    }

    /// Undoes every intervention: everything the block hid is unhidden. Runs
    /// on block deactivation and on app quit.
    func restore() {
        lastKeyEvent = [:]
        restoreHiddenApps()
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

    // MARK: - The loop

    /// One attempt, then the next — until the app is out of sight, the budget
    /// runs out, or the block ends. Every technique is idempotent, so a
    /// repeated attempt costs nothing but a system call.
    private func insist(app: NSRunningApplication, attempt: Int) {
        let probing = isProbing(app)
        guard isActive() || probing else { return finish(app) }
        let budget = probing ? Self.probeAttempts : Self.attempts

        let plan = BlockAttempt.plan(
            attempt: attempt,
            visible: isVisible(app),
            frontmost: isFrontmost(app),
            fullscreen: AccessibilityAccess.isAppFullscreen(pid: app.processIdentifier),
            accessibilityGranted: accessibilityGranted(attempt: attempt),
            keyEventAllowed: keyEventAllowed(app)
        )
        guard !plan.stop, attempt < budget else { return finish(app) }
        perform(plan, on: app)
        if probing { probeFired = probeFired.map { merge($0, plan) } }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.interval) { [weak self] in
            self?.insist(app: app, attempt: attempt + 1)
        }
    }

    private func perform(_ plan: BlockPlan, on app: NSRunningApplication) {
        let pid = app.processIdentifier
        // Keyboard first: it is the slowest to take effect, and while the app
        // still owns a fullscreen Space every other technique is refused.
        if plan.sendExitFullscreenKey {
            FullscreenExit.sendExitFullscreen()
            lastKeyEvent[pid] = Date()
        }
        if plan.sendSpaceLeftKey { FullscreenExit.sendSpaceLeft() }
        if plan.exitFullscreenViaAX { _ = AccessibilityAccess.exitFullscreen(pid: pid) }
        if plan.hide { hideAndRecord(app) }
        if plan.minimize { _ = AccessibilityAccess.minimizeWindows(pid: pid) }
    }

    /// Clears the in-flight marker and reports a diagnostic if this was one.
    private func finish(_ app: NSRunningApplication) {
        running.remove(app.processIdentifier)
        if isProbing(app) { finishProbe(app: app) }
    }

    /// Merges what a further attempt did into what the diagnostic has seen.
    private func merge(_ seen: BlockPlan, _ plan: BlockPlan) -> BlockPlan {
        var merged = seen
        merged.exitFullscreenViaAX = seen.exitFullscreenViaAX || plan.exitFullscreenViaAX
        merged.hide = seen.hide || plan.hide
        merged.minimize = seen.minimize || plan.minimize
        merged.sendExitFullscreenKey = seen.sendExitFullscreenKey || plan.sendExitFullscreenKey
        merged.sendSpaceLeftKey = seen.sendSpaceLeftKey || plan.sendSpaceLeftKey
        return merged
    }

    // MARK: - Diagnostics

    /// Whether this very app is the one under diagnosis.
    private func isProbing(_ app: NSRunningApplication) -> Bool {
        probeReport != nil && probeTarget == app.processIdentifier
    }

    /// Reports the run and clears the stage again.
    private func finishProbe(app: NSRunningApplication) {
        guard let report = probeReport else { return }
        let outcome = Self.probeOutcome(fired: probeFired ?? BlockPlan(), visible: isVisible(app))
        probeReport = nil
        probeTarget = nil
        probeFired = nil
        report(outcome)
    }

    /// The strongest thing that actually happened wins — and an app that is
    /// still on screen after the whole loop says so plainly instead of
    /// claiming a success.
    private static func probeOutcome(fired: BlockPlan, visible: Bool) -> ProbeOutcome {
        guard !visible else { return fired.isEmpty ? .noAction : .failed }
        if fired.isEmpty { return .noAction }
        if fired.sendSpaceLeftKey { return .spaceSwitched }
        if fired.sendExitFullscreenKey || fired.exitFullscreenViaAX { return .unfullscreened }
        return fired.minimize ? .minimized : .hidden
    }

    // MARK: - State

    /// The permission is asked for once, on the first attempt of a loop that
    /// is actually doing something — every later attempt reads the answer.
    private func accessibilityGranted(attempt: Int) -> Bool {
        attempt == 0 ? AccessibilityAccess.requestIfNeeded() : AccessibilityAccess.isTrusted
    }

    private func isVisible(_ app: NSRunningApplication) -> Bool {
        !app.isTerminated && !app.isHidden
    }

    /// Keyboard shortcuts always land in the frontmost app, so only that one
    /// may be sent any.
    private func isFrontmost(_ app: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    private func keyEventAllowed(_ app: NSRunningApplication) -> Bool {
        guard let last = lastKeyEvent[app.processIdentifier] else { return true }
        return Date().timeIntervalSince(last) >= Self.keyEventInterval
    }

    /// Gentle intervention: hide and remember what *we* hid, so restore never
    /// touches anything this app did not hide itself. A refused hide is not an
    /// error here — the loop simply comes back.
    private func hideAndRecord(_ app: NSRunningApplication) {
        guard !app.isHidden, app.hide(), let id = app.bundleIdentifier else { return }
        hiddenApps.add(id)
    }
}
