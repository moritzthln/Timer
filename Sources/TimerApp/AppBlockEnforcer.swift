import AppKit
import TimerCore

/// Keeps blocked apps out of sight. Nothing is destroyed: apps are taken out
/// of fullscreen, hidden, or minimised, and everything the enforcer hid is
/// unhidden again when the block ends.
///
/// v25.3 works in two phases, because macOS leaves no other way: an app that
/// is not active exposes **no** Accessibility windows, so it can neither be
/// inspected nor taken out of fullscreen from the outside (measured: Telegram
/// and WhatsApp, both in fullscreen, both reporting zero AX windows). And
/// `hide()` does succeed on a fullscreen app — it just leaves the Space and
/// its window behind, out of reach for good.
///
/// So: **first** every screen-filling app is visited one after another and
/// dissolved (activate → ⌃⌘F / AX → verify), **then** everything is hidden.
/// Apps that hold no screen skip phase one entirely.
final class AppBlockEnforcer {
    /// Between two attempts of the hide loop.
    private static let interval = 0.2
    /// One burst, ~6 s. The poll re-arms a still-visible app right after.
    private static let attempts = 30
    /// Between two steps of the fullscreen sweep. Slower than the hide loop:
    /// every step waits on a Space switch or an exit animation. Tightening
    /// this to 0.1 s did make the sweep quicker, but it also made it jumpy —
    /// the calmer pace is the one that works (user: "lieber wie davor").
    private static let sweepInterval = 0.25
    /// ~4 s per app, then the sweep moves on and the poll brings it back.
    private static let sweepAttempts = 16
    /// From this step on (~2 s), the Space-left shortcut joins in.
    private static let spaceLeftFrom = 8
    /// One exit-fullscreen shortcut per app per 0.7 s: the exit animation runs
    /// about half a second, and a second shortcut inside it would toggle the
    /// app straight back in.
    private static let keyEventInterval = 0.7
    /// How long the diagnostic watches before it reports.
    private static let probeDelay = 3.5
    /// How long macOS gets to act on a hide before the fallback judges it.
    private static let hideVerifyDelay = 0.3
    /// After this many sweeps that ended without dissolving the app, it is
    /// left alone for a while. Without that, an app that neither lists its
    /// windows nor answers ⌃⌘F would be pulled to the front by every poll
    /// tick — for the whole session, every few seconds.
    private static let sweepFailureLimit = 3
    /// How long such an app is left in peace before the next try.
    private static let sweepBackoff = 60.0
    /// How many trips in a row may come up empty before the app is considered
    /// done. Counting *fruitless* trips instead of trips means three profiles
    /// work as well as two: every window that is actually dissolved resets the
    /// count, so the sweep follows as many Spaces as the app really holds.
    private static let maxFruitlessBounces = 2
    /// Hard ceiling per app and sweep, whatever the progress — a runaway loop
    /// must not be able to walk the Spaces forever.
    private static let sweepStepCeiling = 60
    /// Between leaving the app and coming back — long enough for macOS to
    /// have switched Space, short enough not to feel like a detour.
    private static let bounceDelay = 0.35

    private let preferences: Preferences
    private var hiddenApps = HiddenAppsRecord()
    /// Sweeps that ended without dissolving the app, and until when it is
    /// therefore left alone.
    private var sweepFailures: [pid_t: Int] = [:]
    private var sweepPausedUntil: [pid_t: Date] = [:]
    /// Apps with a hide loop in flight, so the poll never stacks loops.
    private var running: Set<pid_t> = []
    /// When each app last received a keyboard shortcut (throttle memory).
    private var lastKeyEvent: [pid_t: Date] = [:]

    /// Phase one: the apps still to be taken out of fullscreen, the one being
    /// worked on, and how long it has resisted.
    private var sweepQueue: [NSRunningApplication] = []
    private var sweeping: NSRunningApplication?
    private var sweepAttempt = 0
    /// Trips away and back that did not turn up another fullscreen window.
    private var sweepFruitlessBounces = 0
    /// Steps spent on the current app in total, progress or not.
    private var sweepSteps = 0
    /// Phase two: what to hide once no app holds a screen any more.
    private var pendingHide: [NSRunningApplication] = []
    /// Where the user was before the sweep started throwing Spaces around.
    private var focusReturn: NSRunningApplication?

    /// Whether the block is still active — every delayed step drops out as
    /// soon as the session ended, paused, or the shield went off.
    var isActive: () -> Bool = { true }

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Undoes a block that never got to clean up after itself: a crash or a
    /// force quit leaves the apps hidden and the in-memory record gone, so the
    /// persisted list is the only way back. Runs once, at launch.
    func restoreLeftoversFromLastRun() {
        let ids = Set(preferences.hiddenByBlock)
        guard !ids.isEmpty else { return }
        preferences.hiddenByBlock = []
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, ids.contains(id) { _ = app.unhide() }
        }
    }

    /// What a diagnostic run found. The wording is what the "Rechte" tab
    /// prints, so it stays next to the code that produces it.
    enum ProbeOutcome: String {
        case noAction = "kein Eingriff nötig"
        case hidden = "versteckt"
        case unfullscreened = "aus Vollbild geholt, noch sichtbar"
        case failed = "blieb im Vollbild"
    }

    // MARK: - Entry points

    /// Every block event (sweep, launch, activation, poll) comes through here.
    func enforce(app: NSRunningApplication, name: String) {
        let pid = app.processIdentifier
        guard !app.isTerminated, !running.contains(pid) else { return }
        guard sweeping?.processIdentifier != pid,
              !sweepQueue.contains(where: { $0.processIdentifier == pid }),
              !pendingHide.contains(where: { $0.processIdentifier == pid }) else { return }
        running.insert(pid)
        insist(app: app, attempt: 0)
    }

    /// "Vollbild-Block testen" in the Rechte tab: the same machinery against
    /// one app, ignoring the block lists and the session state, reporting what
    /// the app looks like once the dust settles.
    func probe(
        app: NSRunningApplication, name: String,
        report: @escaping (ProbeOutcome) -> Void
    ) {
        let wasHidden = app.isHidden
        let heldScreen = occupiesScreen(app)
        enforce(app: app, name: name)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.probeDelay) { [weak self] in
            guard let self else { return }
            if app.isHidden { return report(wasHidden ? .noAction : .hidden) }
            if self.occupiesScreen(app) { return report(.failed) }
            report(heldScreen ? .unfullscreened : .noAction)
        }
    }

    /// Undoes every intervention: everything the block hid is unhidden. Runs
    /// on block deactivation and on app quit.
    func restore() {
        lastKeyEvent = [:]
        sweepFailures = [:]
        sweepPausedUntil = [:]
        abortSweep()
        restoreHiddenApps()
    }

    /// Kept as the poll's call site — there is no cover window any more.
    func releaseCover() {}

    /// Unhides every app this enforcer hid and clears the record. Apps the
    /// user hid manually were never recorded and stay untouched.
    private func restoreHiddenApps() {
        let ids = hiddenApps.drain()
        preferences.hiddenByBlock = []
        guard !ids.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, ids.contains(id) {
                _ = app.unhide()
            }
        }
    }

    // MARK: - The hide loop

    /// One attempt, then the next — until the app is out of the way, it turns
    /// out to hold a screen (then phase one takes over), or the block ends.
    private func insist(app: NSRunningApplication, attempt: Int) {
        guard isActive() else { return finish(app) }
        let plan = BlockAttempt.plan(
            attempt: attempt,
            hidden: app.isHidden || app.isTerminated,
            occupiesScreen: occupiesScreen(app),
            accessibilityGranted: accessibilityGranted(attempt: attempt)
        )
        guard !plan.stop, attempt < Self.attempts else { return finish(app) }
        if plan.sweepFullscreen {
            finish(app)
            // An app that has resisted the sweep often enough is left in peace
            // for a minute and simply taken off the screen. Its Space survives
            // that, which is the lesser evil: the alternative is the app being
            // yanked to the front every few seconds for the whole session.
            guard !isSweepPaused(app) else { return hideAndRecord(app) }
            return enqueueSweep(app)
        }
        if plan.unhide { _ = app.unhide() }
        if plan.hide { hideAndRecord(app) }
        if plan.minimize { _ = AccessibilityAccess.minimizeWindows(pid: app.processIdentifier) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.interval) { [weak self] in
            self?.insist(app: app, attempt: attempt + 1)
        }
    }

    private func finish(_ app: NSRunningApplication) {
        running.remove(app.processIdentifier)
    }

    // MARK: - Phase one: dissolve the fullscreen apps, one at a time

    private func enqueueSweep(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard sweeping?.processIdentifier != pid,
              !sweepQueue.contains(where: { $0.processIdentifier == pid }) else { return }
        sweepQueue.append(app)
        if focusReturn == nil { focusReturn = NSWorkspace.shared.frontmostApplication }
        startNextSweep()
    }

    private func startNextSweep() {
        guard sweeping == nil else { return }
        guard isActive() else { return abortSweep() }
        guard !sweepQueue.isEmpty else { return hidePending() }
        sweeping = sweepQueue.removeFirst()
        sweepAttempt = 0
        sweepFruitlessBounces = 0
        sweepSteps = 0
        scheduleSweepStep()
    }

    private func scheduleSweepStep() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.sweepInterval) { [weak self] in
            self?.sweepStep()
        }
    }

    /// The app has the screen: bring it to the front — the only way its
    /// windows become reachable at all — and take it out of fullscreen. It is
    /// deliberately *not* hidden here; that is phase two's job, once every
    /// fullscreen app has been dissolved.
    private func sweepStep() {
        guard let app = sweeping else { return }
        guard isActive() else { return abortSweep() }
        guard !app.isTerminated, occupiesScreen(app) else { return finishSweepStep(app, done: true) }
        guard sweepAttempt < Self.sweepAttempts, sweepSteps < Self.sweepStepCeiling
        else { return finishSweepStep(app, done: false) }
        sweepAttempt += 1
        sweepSteps += 1

        // The precise route first. `AXFullScreen = false` addresses the window
        // itself, whichever Space it lives on and whichever window has focus.
        // The keyboard shortcut cannot do that: it hits the *focused* window,
        // and an app like Chrome commonly has a fullscreen window on its own
        // Space **and** a normal one on the desktop (measured: #3
        // fullscreen=true 1512x827, #4 fullscreen=false 1512x884). Activating
        // brings the normal one forward, so ⌃⌘F pushed that one into
        // fullscreen while AX pulled the other one out — Chrome never left.
        let axState = AccessibilityAccess.fullscreenState(pid: app.processIdentifier)
        if axState == true {
            // One write covers every fullscreen window Accessibility can see,
            // which is what makes two windows sharing one Space (Split View)
            // fall out together.
            _ = AccessibilityAccess.exitFullscreen(pid: app.processIdentifier)
            // Progress buys a fresh budget: an app with several fullscreen
            // Spaces should not run out of steps halfway through them.
            sweepAttempt = 0
            sweepFruitlessBounces = 0
            return scheduleSweepStep()
        }
        if axState == false {
            // Accessibility sees the windows and none of them is fullscreen —
            // but it only ever sees the ones on the active Space. If the app
            // owns another window elsewhere, that is where the next fullscreen
            // sits, and the only way in is to leave the app and come back:
            // macOS then switches to whatever its front window is.
            guard sweepFruitlessBounces < Self.maxFruitlessBounces,
                  FullscreenWindows.hasWindowOnAnotherSpace(pid: app.processIdentifier)
            else { return finishSweepStep(app, done: true) }
            sweepFruitlessBounces += 1
            bounce(app)
            return scheduleSweepStep()
        }

        // Blind: the app is on its own Space and lists no windows at all
        // (Telegram, WhatsApp). Only the app itself can act on them, so it has
        // to come forward and take the shortcut.
        guard isFrontmost(app) else {
            // The Space switch takes a moment; keep asking until it lands.
            app.activate()
            return scheduleSweepStep()
        }
        if keyEventAllowed(app) {
            FullscreenExit.sendExitFullscreen()
            lastKeyEvent[app.processIdentifier] = Date()
        }
        if sweepAttempt >= Self.spaceLeftFrom { FullscreenExit.sendSpaceLeft() }
        scheduleSweepStep()
    }

    /// This app is done with — either dissolved (then it joins phase two) or
    /// out of budget (then the poll brings it back later).
    private func finishSweepStep(_ app: NSRunningApplication, done: Bool) {
        sweeping = nil
        let pid = app.processIdentifier
        if done {
            sweepFailures[pid] = nil
            sweepPausedUntil[pid] = nil
            if !app.isTerminated { pendingHide.append(app) }
        } else {
            let failures = (sweepFailures[pid] ?? 0) + 1
            sweepFailures[pid] = failures
            if failures >= Self.sweepFailureLimit {
                sweepPausedUntil[pid] = Date().addingTimeInterval(Self.sweepBackoff)
                sweepFailures[pid] = 0
            }
        }
        startNextSweep()
    }

    /// Leaves the app and comes straight back, which lands on its front
    /// window — a fullscreen one, if any is left. Finder is the way out
    /// because it always runs and owns the desktop; the Timer has no window
    /// to switch to and would not move the Space at all.
    private func bounce(_ app: NSRunningApplication) {
        let elsewhere = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == "com.apple.finder"
        }
        elsewhere?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.bounceDelay) { [weak self] in
            guard let self, self.sweeping?.processIdentifier == app.processIdentifier else { return }
            app.activate()
        }
    }

    private func isSweepPaused(_ app: NSRunningApplication) -> Bool {
        guard let until = sweepPausedUntil[app.processIdentifier] else { return false }
        return until > Date()
    }

    // MARK: - Phase two: hide everything that was dissolved

    private func hidePending() {
        let apps = pendingHide
        pendingHide = []
        for app in apps where !app.isTerminated { hideAndRecord(app) }
        handBackFocus(except: apps)
        // Minimising is only for what refused the hide. Doing it up front put
        // windows in the Dock that were already gone — the user saw an app
        // that was "nur minimiert" instead of hidden. macOS needs a moment to
        // flip the flag, so the check comes after one.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideVerifyDelay) { [weak self] in
            guard let self, self.isActive() else { return }
            for app in apps where !app.isTerminated && !app.isHidden {
                _ = AccessibilityAccess.minimizeWindows(pid: app.processIdentifier)
            }
        }
    }

    /// Give the screen back to whoever had it before the sweep — unless that
    /// app was hidden in the meantime, in which case macOS picks for itself.
    private func handBackFocus(except hidden: [NSRunningApplication]) {
        defer { focusReturn = nil }
        guard let back = focusReturn, !back.isTerminated, !back.isHidden,
              !hidden.contains(where: { $0.processIdentifier == back.processIdentifier })
        else { return }
        back.activate()
    }

    private func abortSweep() {
        sweeping = nil
        sweepQueue = []
        pendingHide = []
        focusReturn = nil
    }

    // MARK: - State

    /// Whether the app takes up a whole screen right now. Accessibility
    /// answers for the active app; for every other one only the window server
    /// still sees the windows (an inactive fullscreen app reports none).
    private func occupiesScreen(_ app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        let ax = AccessibilityAccess.fullscreenState(pid: pid)
        if ax == true { return true }
        // Geometry is the second opinion, not the first: it is what still sees
        // the fullscreen window of a *hidden* app (the repair case), but it
        // cannot tell Chrome's own fullscreen from a maximised window.
        if FullscreenWindows.hasFullscreenWindow(pid: pid) { return true }
        // Accessibility going quiet on a visible app that demonstrably owns
        // windows is the signature of an app sitting on its own Space. There
        // is no way to find out from here — the sweep brings it forward and
        // asks properly, and lets it go again in one step if it was nothing.
        return ax == nil && !app.isHidden && FullscreenWindows.hasContentWindow(pid: pid)
    }

    /// The permission is asked for once, on the first attempt of a loop; every
    /// later attempt just reads the answer.
    private func accessibilityGranted(attempt: Int) -> Bool {
        attempt == 0 ? AccessibilityAccess.requestIfNeeded() : AccessibilityAccess.isTrusted
    }

    private func isFrontmost(_ app: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    private func keyEventAllowed(_ app: NSRunningApplication) -> Bool {
        guard let last = lastKeyEvent[app.processIdentifier] else { return true }
        return Date().timeIntervalSince(last) >= Self.keyEventInterval
    }

    /// Gentle intervention: hide and remember what *we* hid, so restore never
    /// touches anything this app did not hide itself.
    private func hideAndRecord(_ app: NSRunningApplication) {
        guard !app.isHidden, app.hide(), let id = app.bundleIdentifier else { return }
        hiddenApps.add(id)
        // Write through, so a crash or a force quit cannot strand the app.
        if !preferences.hiddenByBlock.contains(id) {
            preferences.hiddenByBlock.append(id)
        }
    }
}
