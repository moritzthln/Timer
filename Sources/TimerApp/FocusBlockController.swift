import AppKit
import TimerCore

/// Enforces the focus block while a focus session runs — gently since v16:
/// apps are hidden (never terminated) and restored when the block ends, and
/// blocked browser tabs stay open while the browser switches away from them.
/// Blocklist mode intervenes on blocklisted apps and browser tabs; allowlist
/// mode (v15) on unlisted regular apps and tabs on unlisted hosts. The mode
/// is consulted per event/poll, so a mid-session mode change applies
/// naturally on the next event.
///
/// v25 makes it stubborn: every app event hands the app to
/// `AppBlockEnforcer`, whose loop repeats every technique until the app is out
/// of sight, and the 1 s poll re-arms that loop for every blocked app that is
/// still visible. Fullscreen re-entry and Space switches post no workspace
/// notification, so the poll is the only thing that catches them.
///
/// Blocked websites are handled in the same spirit: the tab stays open while
/// the browser switches away from it. The v22 site cover and the v16 popup are
/// both gone — v25 wants the block to pass unnoticed, not to announce itself.
///
/// v24 adds the emergency branch on top: while an emergency session runs,
/// both arms follow the emergency lists with allowlist semantics — regardless
/// of the shield, the block mode, and whether a timer runs at all. Nothing
/// below changes for it; only which list `blockTarget` and the browser poll
/// consult.
final class FocusBlockController {
    private let preferences: Preferences
    /// v25: runs the insisting block loop (shortcut out of fullscreen, hide,
    /// minimise — repeated until the app is gone) and owns the restore record.
    private let enforcer: AppBlockEnforcer
    /// v24: whether an emergency session runs right now — read live per event
    /// and per poll, exactly like the block mode, so starting or ending one
    /// mid-session applies on the next event.
    var emergencyActive: () -> Bool = { false }
    private var active = false
    /// The last phase the engine reported; the emergency reconciles against
    /// it without the engine having to say anything.
    private var lastPhase: TimerEngine.Phase = .idle
    /// Whether the running block currently follows the emergency lists.
    private var emergencyEngaged = false
    private var pollTimer: Foundation.Timer?
    private var launchObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?
    /// Bundle ids whose tab-switch scripting failed this activation (Arc
    /// when its Chromium-style commands are rejected); they use the v15
    /// close fallback until the next activation probes again.
    private var tabSwitchUnsupported: Set<String> = []


    init(preferences: Preferences) {
        self.preferences = preferences
        enforcer = AppBlockEnforcer(preferences: preferences)
        // A block that was cut short (crash, force quit) left its apps hidden.
        enforcer.restoreLeftoversFromLastRun()
        // Delayed loop attempts stop as soon as the block is off.
        enforcer.isActive = { [weak self] in self?.active ?? false }
    }

    /// Reevaluates against the engine phase; idempotent.
    func update(phase: TimerEngine.Phase) {
        lastPhase = phase
        reconcile()
    }

    /// v24: an emergency session started or ended. Same reconcile — the
    /// emergency is just a second reason for the block to run.
    func updateEmergency() {
        reconcile()
    }

    /// The one place that decides whether the block runs and under which
    /// rules. The emergency outranks everything: it blocks regardless of
    /// `focusBlockEnabled`, of the block mode, and of whether a timer runs.
    private func reconcile() {
        let emergency = emergencyActive()
        let emergencyChanged = emergency != emergencyEngaged
        emergencyEngaged = emergency
        let shouldBeActive = emergency || FocusBlockRules.isActive(
            phase: lastPhase, enabled: preferences.focusBlockEnabled
        )
        if shouldBeActive != active {
            active = shouldBeActive
            if active {
                beginBlocking()
            } else {
                endBlocking()
            }
        } else if active, emergencyChanged {
            // The authoritative list changed underneath a running block (an
            // emergency started or ended while a focus session runs): undo
            // what the old rules hid, then sweep with the new ones.
            restoreBlockedApps()
            sweepRunningApps()
        }
    }

    private func beginBlocking() {
        tabSwitchUnsupported = []
        // A block without this permission silently does nothing to fullscreen
        // apps — better to say so than to look broken.
        AccessibilityAccess.warnIfMissing()
        sweepRunningApps()
        startWatching()
    }

    private func endBlocking() {
        stopWatching()
        restoreBlockedApps()
    }

    /// Undoes everything the block did: every app it hid is unhidden again.
    /// Runs on every block deactivation and on app quit
    /// (prepareForTermination). Apps the user hid manually were never recorded
    /// and stay untouched.
    func restoreBlockedApps() {
        enforcer.restore()
    }

    // MARK: - Diagnostics

    /// v21 "Rechte" tab: runs the escalation ladder once against whatever is
    /// in front right now — no block list, no running session. The Timer
    /// itself is never a target: the button that starts this sits in its own
    /// settings window, so the caller gives the user a moment to switch to
    /// the app he wants to see blocked.
    func testFullscreenBlock(report: @escaping (String) -> Void) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != NSRunningApplication.current.processIdentifier
        else {
            report("keine andere App im Vordergrund")
            return
        }
        let name = app.localizedName ?? "App"
        enforcer.probe(app: app, name: name) { outcome in
            report("\(name) — \(outcome.rawValue)")
        }
    }

    // MARK: - Apps

    /// Activation sweep over the already-running apps, per the current mode.
    private func sweepRunningApps() {
        for app in NSWorkspace.shared.runningApplications {
            if let name = blockTarget(app) {
                enforcer.enforce(app: app, name: name)
            }
        }
    }

    /// The active mode's block predicate, folded together with the name to
    /// display: non-nil means "this app must go away right now".
    private func blockTarget(_ app: NSRunningApplication) -> String? {
        // v24: the emergency session takes precedence over shield and mode.
        // Its empty list means "only the essentials" — see shouldHide.
        if emergencyActive() {
            return allowlistTarget(
                app, allowed: preferences.emergencyApps,
                allowedDomains: preferences.emergencyDomains, emptyListBlocksAll: true
            )
        }
        switch preferences.blockMode {
        case .blocklist:
            guard let id = app.bundleIdentifier, !isEssential(id),
                  let entry = preferences.blockedApps.first(where: { $0.bundleID == id })
            else { return nil }
            return entry.name.isEmpty ? (app.localizedName ?? "App") : entry.name
        case .allowlist:
            return allowlistTarget(
                app, allowed: preferences.allowedApps,
                allowedDomains: preferences.allowedDomains
            )
        }
    }

    /// Timer, Finder and System Settings stay reachable in *every* mode. The
    /// allowlist arm has always covered them; the blocklist did not, so an
    /// entry added through "Andere…" could lock the user out of his own
    /// settings — or make the Timer hide itself.
    private func isEssential(_ bundleID: String) -> Bool {
        AllowlistRules.essentialBundleIDs.contains(bundleID)
            || bundleID == Bundle.main.bundleIdentifier
    }

    /// Allowlist app arm, shared by the v15 mode and the v24 emergency:
    /// regular user apps only — the pure rule covers the allowed set, the
    /// essential set (Timer, Finder, System Settings, so settings and files
    /// stay reachable), and the empty-list guard. The running Timer binary is
    /// additionally protected via its live bundle ID (covers dev builds whose
    /// ID differs from the packaged one).
    private func allowlistTarget(
        _ app: NSRunningApplication, allowed: [BlockedApp], allowedDomains: [String],
        emptyListBlocksAll: Bool = false
    ) -> String? {
        guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return nil }
        // An allowed website needs a browser to be openable in, so allowing
        // one keeps the supported browsers reachable — restricted to exactly
        // those sites by the tab arm.
        let essential = AllowlistRules.essentials(
            withBrowsers: Set(BrowserScripting.supported.map(\.bundleID)),
            allowedDomains: allowedDomains
        ).union([Bundle.main.bundleIdentifier].compactMap { $0 })
        guard AllowlistRules.shouldHide(
            bundleID: id, allowed: Set(allowed.map(\.bundleID)), essential: essential,
            emptyListBlocksAll: emptyListBlocksAll
        ) else { return nil }
        return app.localizedName ?? "App"
    }

    /// Launch/activation handler; reads the mode per event. Activation
    /// matters because hidden apps keep running: clicking one in the Dock
    /// unhides it without a launch event, so it must be hidden again.
    private func handleLaunchOrActivate(_ app: NSRunningApplication) {
        guard let name = blockTarget(app) else { return }
        enforcer.enforce(app: app, name: name)
    }

    private func startWatching() {
        launchObserver = workspaceObserver(for: NSWorkspace.didLaunchApplicationNotification)
        activateObserver = workspaceObserver(for: NSWorkspace.didActivateApplicationNotification)
        // v25: 1 s instead of 2. The poll is what makes the block relentless —
        // it re-arms the loop for every app that is still visible — so it ticks
        // at the rate at which the user should stop noticing the block at all.
        pollTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        pollTimer?.tolerance = 0.2
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    private func workspaceObserver(for name: Notification.Name) -> NSObjectProtocol {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: name, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, self.active,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self.handleLaunchOrActivate(app)
        }
    }

    private func stopWatching() {
        for observer in [launchObserver, activateObserver].compactMap({ $0 }) {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        launchObserver = nil
        activateObserver = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Safety poll

    /// The 1 s poll. v18 re-checked only the frontmost app, because fullscreen
    /// re-entry and Space switches post no workspace notification. That left a
    /// hole the user ran into (report: "nicht alle Apps werden aus Vollbild
    /// geholt und gehidet"): a blocked app that is not in front — on its own
    /// fullscreen Space, or simply behind something — got exactly one burst at
    /// activation time and was never looked at again. v25 sweeps *all* of
    /// them every tick; the enforcer ignores apps whose loop is still running
    /// and apps that are already out of sight, so a clean tick costs one
    /// array walk. Both arms read the mode per tick.
    private func poll() {
        guard active else { return }
        sweepRunningApps()
        pollBrowsers()
    }

    // MARK: - Browsers

    private func pollBrowsers() {
        // v24: the emergency domains are an allowlist too, and they outrank
        // whatever the shield would do.
        if emergencyActive() {
            pollBrowsersAllowlist(domains: preferences.emergencyDomains)
            return
        }
        switch preferences.blockMode {
        case .blocklist:
            pollBrowsersBlocklist()
        case .allowlist:
            pollBrowsersAllowlist(domains: preferences.allowedDomains)
        }
    }

    private func pollBrowsersBlocklist() {
        let domains = preferences.blockedDomains
        guard !domains.isEmpty else { return }
        let blocked: (String?) -> Bool = { host in
            guard let host else { return false }
            return domains.contains { FocusBlockRules.domainMatches(host: host, entry: $0) }
        }
        for browser in runningSupportedBrowsers() {
            guard let urlString = BrowserScripting.run(browser.readURL),
                  let host = FocusBlockRules.blockableHost(urlString: urlString),
                  blocked(host) else { continue }
            switchAway(in: browser, neighborBlocked: blocked)
        }
    }

    /// Allowlist tab arm, shared by the v15 mode and the v24 emergency. The
    /// empty-list guard keeps the AppleScript probes (and their permission
    /// prompts) away entirely while nothing can match.
    private func pollBrowsersAllowlist(domains: [String]) {
        guard !domains.isEmpty else { return }
        let blocked: (String?) -> Bool = { host in
            AllowlistRules.shouldCloseTab(host: host, allowedDomains: domains)
        }
        for browser in runningSupportedBrowsers() {
            guard let urlString = BrowserScripting.run(browser.readURL) else { continue }
            // A nil host (internal and new-tab pages) is never a hit — that
            // decision belongs to the pure rule, not here.
            guard blocked(FocusBlockRules.blockableHost(urlString: urlString)) else { continue }
            switchAway(in: browser, neighborBlocked: blocked)
        }
    }

    /// v16 gentle tab blocking: the blocked tab stays open in the background
    /// while the browser switches to a neighbor tab — or to a fresh empty
    /// tab when there is no (unblocked) neighbor. A browser whose switch
    /// scripting errors (Arc's Chromium compatibility is only claimed) falls
    /// back to the v15 close for the rest of this block activation.
    private func switchAway(
        in browser: BrowserScripting.Browser, neighborBlocked: (String?) -> Bool
    ) {
        guard !tabSwitchUnsupported.contains(browser.bundleID) else {
            _ = BrowserScripting.runVoid(browser.closeTab)
            return
        }
        guard let info = BrowserScripting.parseTabInfo(BrowserScripting.run(browser.tabInfo)) else {
            fallBackToClose(browser)
            return
        }
        let target = TabSwitchPlan.target(activeIndex: info.index, count: info.count) { index in
            let neighborURL = BrowserScripting.run(browser.tabURL(at: index))
            return neighborBlocked(FocusBlockRules.blockableHost(urlString: neighborURL))
        }
        let script: String
        switch target {
        case .neighbor(let index): script = browser.activateTab(at: index)
        case .newTab: script = browser.newTab
        }
        if !BrowserScripting.runVoid(script) {
            fallBackToClose(browser)
        }
    }

    /// Runtime capability decision, made at most once per block activation:
    /// this browser cannot switch tabs — close the blocked tab v15-style
    /// now and for every further hit in this activation (no repeated probes).
    private func fallBackToClose(_ browser: BrowserScripting.Browser) {
        tabSwitchUnsupported.insert(browser.bundleID)
        _ = BrowserScripting.runVoid(browser.closeTab)
    }

    private func runningSupportedBrowsers() -> [BrowserScripting.Browser] {
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return BrowserScripting.supported.filter { runningIDs.contains($0.bundleID) }
    }
}
