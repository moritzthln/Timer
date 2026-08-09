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
/// v18 makes it fullscreen-proof: every app event runs through
/// `AppBlockEnforcer`'s escalation ladder instead of a single `hide()`, and
/// the 2 s poll re-checks the frontmost app — the only way to catch an app
/// the user pushed back into fullscreen or a Space switch, neither of which
/// posts a workspace notification. v21 gave that ladder the Space escape, so
/// the poll is also what catches a ⌘-Tab back into the blocked app: within
/// ~2 s the escape pulls the screen away from it again.
final class FocusBlockController {
    private let preferences: Preferences
    private let overlay: BlockOverlayController
    /// v18: runs the escalation ladder (hide → un-fullscreen + hide →
    /// v21 Space escape → cover overlay) and owns the restore record.
    private let enforcer: AppBlockEnforcer
    /// The ladder's last two rungs — the key-capable full-screen cover that
    /// both performs the v21 Space escape and stays as the v18 last resort.
    private let cover = BlockCoverController()
    /// Live remaining session seconds, read at popup display moments.
    private let remainingSeconds: () -> Int
    private var active = false
    private var pollTimer: Foundation.Timer?
    private var launchObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?
    /// Bundle ids whose tab-switch scripting failed this activation (Arc
    /// when its Chromium-style commands are rejected); they use the v15
    /// close fallback until the next activation probes again.
    private var tabSwitchUnsupported: Set<String> = []

    init(
        preferences: Preferences,
        overlay: BlockOverlayController,
        remainingSeconds: @escaping () -> Int
    ) {
        self.preferences = preferences
        self.overlay = overlay
        self.remainingSeconds = remainingSeconds
        enforcer = AppBlockEnforcer(
            popup: overlay, cover: cover, remainingSeconds: remainingSeconds
        )
        // Delayed ladder steps stop as soon as the block is off.
        enforcer.isActive = { [weak self] in self?.active ?? false }
    }

    /// Reevaluates against the engine phase; idempotent.
    func update(phase: TimerEngine.Phase) {
        let shouldBeActive = FocusBlockRules.isActive(
            phase: phase, enabled: preferences.focusBlockEnabled
        )
        guard shouldBeActive != active else { return }
        active = shouldBeActive
        if active {
            tabSwitchUnsupported = []
            sweepRunningApps()
            startWatching()
        } else {
            stopWatching()
            restoreBlockedApps()
        }
    }

    /// Undoes everything the block did: every app it hid is unhidden and any
    /// cover overlay comes down. Runs on every block deactivation and on app
    /// quit (prepareForTermination). Apps the user hid manually were never
    /// recorded and stay untouched.
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
        switch preferences.blockMode {
        case .blocklist:
            guard let id = app.bundleIdentifier,
                  let entry = preferences.blockedApps.first(where: { $0.bundleID == id })
            else { return nil }
            return entry.name.isEmpty ? (app.localizedName ?? "App") : entry.name
        case .allowlist:
            guard shouldHideInAllowlist(app) else { return nil }
            return app.localizedName ?? "App"
        }
    }

    /// Allowlist app arm: regular user apps only — the pure rule covers the
    /// allowed set, the essential set, and the empty-list guard. The running
    /// Timer binary is additionally protected via its live bundle ID (covers
    /// dev builds whose ID differs from the packaged one).
    private func shouldHideInAllowlist(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return false }
        let essential = AllowlistRules.essentialBundleIDs.union(
            [Bundle.main.bundleIdentifier].compactMap { $0 }
        )
        return AllowlistRules.shouldHide(
            bundleID: id,
            allowed: Set(preferences.allowedApps.map(\.bundleID)),
            essential: essential
        )
    }

    /// Launch/activation handler; reads the mode per event. Activation
    /// matters because hidden apps keep running: clicking one in the Dock
    /// unhides it without a launch event, so it must be hidden again.
    private func handleLaunchOrActivate(_ app: NSRunningApplication) {
        guard let name = blockTarget(app) else {
            // Something harmless came forward, so whatever the ladder covered
            // is not frontmost anymore — the cover goes immediately instead
            // of waiting for the next poll.
            enforcer.releaseCover()
            return
        }
        enforcer.enforce(app: app, name: name)
    }

    private func startWatching() {
        launchObserver = workspaceObserver(for: NSWorkspace.didLaunchApplicationNotification)
        activateObserver = workspaceObserver(for: NSWorkspace.didActivateApplicationNotification)
        pollTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        pollTimer?.tolerance = 0.5 // v8 energy audit
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

    /// The 2 s poll, v18: the frontmost app is re-checked before the
    /// browsers. Fullscreen re-entry and Space switches fire no reliable
    /// workspace notification, so this tick is the only thing that catches
    /// them — and it is what makes the block relentless instead of
    /// one-shot. Both arms read the mode per tick.
    private func poll() {
        guard active else { return }
        enforceFrontmostApp()
        pollBrowsers()
    }

    /// Runs whatever is in front right now through the escalation ladder
    /// again if the active mode blocks it. Every ladder rung is idempotent,
    /// so re-running costs nothing while the app stays hidden. Anything
    /// harmless in front means no cover is warranted.
    private func enforceFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        if let name = blockTarget(app) {
            enforcer.enforce(app: app, name: name)
        } else {
            enforcer.releaseCover()
        }
    }

    // MARK: - Browsers

    private func pollBrowsers() {
        switch preferences.blockMode {
        case .blocklist: pollBrowsersBlocklist()
        case .allowlist: pollBrowsersAllowlist()
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
                  let host = URL(string: urlString)?.host else { continue }
            let matched = domains.first { FocusBlockRules.domainMatches(host: host, entry: $0) }
            if let matched {
                switchAway(in: browser, neighborBlocked: blocked)
                overlay.show(target: matched, remainingSeconds: remainingSeconds())
            }
        }
    }

    /// Allowlist tab arm. The empty-list guard keeps the AppleScript probes
    /// (and their permission prompts) away entirely while nothing can match.
    private func pollBrowsersAllowlist() {
        let domains = preferences.allowedDomains
        guard !domains.isEmpty else { return }
        for browser in runningSupportedBrowsers() {
            guard let urlString = BrowserScripting.run(browser.readURL) else { continue }
            let host = URL(string: urlString)?.host
            guard AllowlistRules.shouldCloseTab(host: host, allowedDomains: domains),
                  let host else { continue }
            switchAway(in: browser) { neighborHost in
                AllowlistRules.shouldCloseTab(host: neighborHost, allowedDomains: domains)
            }
            overlay.show(target: host, remainingSeconds: remainingSeconds())
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
            return neighborBlocked(neighborURL.flatMap { URL(string: $0)?.host })
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
