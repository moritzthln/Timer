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
///
/// v22 gives blocked *websites* the same two-stage treatment the apps got:
/// the tab is covered first (`SiteCoverPlan`, cover over the browser's content
/// area only, chrome untouched) and switched away only after ~10 s of the user
/// staying. Arbitration with the app ladder is one rule — an app cover on
/// screen outranks any site cover — enforced here (`cover.isShowingApp`) and
/// in `BlockCoverController`, which owns the single window and its mode.
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
    /// v22: which blocked host is covered right now, in which browser, and
    /// since when — the clock `SiteCoverPlan` measures against.
    private var siteCover: SiteCover?

    /// The live site cover (v22). Property order is the memberwise init order.
    private struct SiteCover {
        let host: String
        let browserID: String
        let since: Date
    }

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
            // Build the cover's view tree while nothing is urgent, so the
            // first real block does not pay for it.
            cover.prewarm()
            sweepRunningApps()
            startWatching()
        } else {
            stopWatching()
            // Takes both covers with it — see `restoreBlockedApps()`.
            restoreBlockedApps()
        }
    }

    /// Undoes everything the block did: every app it hid is unhidden and any
    /// cover overlay comes down — the v21 app cover and the v22 site cover
    /// alike, since `restore()` clears the window whatever it shows. Runs on
    /// every block deactivation and on app quit (prepareForTermination). Apps
    /// the user hid manually were never recorded and stay untouched.
    func restoreBlockedApps() {
        siteCover = nil
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
        // v22: leaving the covered browser takes its site cover along right
        // away instead of at the next poll. The Timer coming forward is not
        // leaving — a click on the cover itself activates it, and the page
        // underneath must not be handed back for that.
        if app.isActive, !isSelf(app), app.bundleIdentifier != siteCover?.browserID {
            dropSiteCover()
        }
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
        let frontmost = NSWorkspace.shared.frontmostApplication
        // A site cover whose browser is gone (quit, or the user left for a
        // non-browser app) has nobody left to check it; the per-browser path
        // below only sees browsers that are still running.
        if !isSelf(frontmost),
           BrowserScripting.browser(forBundleID: frontmost?.bundleIdentifier) == nil {
            dropSiteCover()
        }
        switch preferences.blockMode {
        case .blocklist: pollBrowsersBlocklist(frontmost: frontmost)
        case .allowlist: pollBrowsersAllowlist(frontmost: frontmost)
        }
    }

    private func pollBrowsersBlocklist(frontmost: NSRunningApplication?) {
        let domains = preferences.blockedDomains
        guard !domains.isEmpty else { dropSiteCover(); return }
        let blocked: (String?) -> Bool = { host in
            guard let host else { return false }
            return domains.contains { FocusBlockRules.domainMatches(host: host, entry: $0) }
        }
        for browser in runningSupportedBrowsers() {
            guard let urlString = BrowserScripting.run(browser.readURL),
                  let host = FocusBlockRules.blockableHost(urlString: urlString) else { continue }
            // The configured entry, not the raw host: it is what the popup and
            // the cover show, and it keeps one clock across a site's
            // subdomains.
            let matched = domains.first { FocusBlockRules.domainMatches(host: host, entry: $0) }
            handleTab(
                browser: browser, hit: matched, frontmost: frontmost, neighborBlocked: blocked
            )
        }
    }

    /// Allowlist tab arm. The empty-list guard keeps the AppleScript probes
    /// (and their permission prompts) away entirely while nothing can match.
    private func pollBrowsersAllowlist(frontmost: NSRunningApplication?) {
        let domains = preferences.allowedDomains
        guard !domains.isEmpty else { dropSiteCover(); return }
        for browser in runningSupportedBrowsers() {
            guard let urlString = BrowserScripting.run(browser.readURL) else { continue }
            let host = FocusBlockRules.blockableHost(urlString: urlString)
            // A nil host (internal and new-tab pages) is never a hit — that
            // decision belongs to the pure rule, not here.
            let hit = AllowlistRules.shouldCloseTab(host: host, allowedDomains: domains)
                ? host : nil
            handleTab(browser: browser, hit: hit, frontmost: frontmost) { neighborHost in
                AllowlistRules.shouldCloseTab(host: neighborHost, allowedDomains: domains)
            }
        }
    }

    // MARK: - Site cover (v22)

    /// One poll tick for one browser. `hit` is the blocked (blocklist) or
    /// non-allowed (allowlist) host of its front window's active tab, nil when
    /// the tab is fine.
    ///
    /// The cover is only earned by the browser the user is actually in; a
    /// background browser's blocked tab is switched away immediately, exactly
    /// as before v22. An app cover on screen outranks the site cover, so the
    /// whole friendly rung stands back while one is up.
    private func handleTab(
        browser: BrowserScripting.Browser,
        hit: String?,
        frontmost: NSRunningApplication?,
        neighborBlocked: (String?) -> Bool
    ) {
        guard !cover.isShowingApp, isCoverFront(browser, frontmost: frontmost) else {
            if siteCover?.browserID == browser.bundleID { dropSiteCover() }
            if let hit {
                switchAwayAndAnnounce(browser: browser, target: hit, neighborBlocked: neighborBlocked)
            }
            return
        }
        let current = siteCover.flatMap { $0.browserID == browser.bundleID ? $0 : nil }
        switch SiteCoverPlan.next(
            host: hit, coveredHost: current?.host, coveredSince: current?.since, now: Date()
        ) {
        case .cover(let host):
            showSiteCover(host: host, browser: browser, since: nil, neighborBlocked: neighborBlocked)
        case .keepCovering:
            guard let current else { return }
            showSiteCover(
                host: current.host, browser: browser, since: current.since,
                neighborBlocked: neighborBlocked
            )
        case .switchAway:
            dropSiteCover()
            if let hit {
                switchAwayAndAnnounce(browser: browser, target: hit, neighborBlocked: neighborBlocked)
            }
        case .dropCover:
            dropSiteCover()
        }
    }

    /// Puts the cover over the browser's content area. `since` nil starts the
    /// 10 s clock, an existing date keeps the running one — so a refresh
    /// follows a moved window and updates the countdown without buying the
    /// user extra time. No room for a readable cover (mini window, browser
    /// mostly off-screen) means the friendly rung is skipped: the tab switch
    /// runs right away instead.
    private func showSiteCover(
        host: String, browser: BrowserScripting.Browser, since: Date?,
        neighborBlocked: (String?) -> Bool
    ) {
        guard let frame = siteCoverFrame(for: browser),
              cover.showSite(host: host, frame: frame, remainingSeconds: remainingSeconds())
        else {
            dropSiteCover()
            switchAwayAndAnnounce(browser: browser, target: host, neighborBlocked: neighborBlocked)
            return
        }
        siteCover = SiteCover(host: host, browserID: browser.bundleID, since: since ?? Date())
    }

    /// The frame the cover may occupy inside this browser's front window, or
    /// nil when there is no window or no room.
    private func siteCoverFrame(for browser: BrowserScripting.Browser) -> NSRect? {
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == browser.bundleID }),
            let window = BrowserWindowBounds.frontWindowFrame(pid: app.processIdentifier)
        else { return nil }
        return BrowserChromeInsets.contentRect(
            windowFrame: window, bundleID: browser.bundleID,
            screenFrame: BrowserWindowBounds.screenFrame(containing: window)
        )
    }

    /// Whether this browser counts as the one in front. The Timer itself
    /// counts as the covered browser: clicking the cover activates the Timer
    /// (the click has to land somewhere), and that must not read as the user
    /// having left — the clock keeps running instead.
    private func isCoverFront(
        _ browser: BrowserScripting.Browser, frontmost: NSRunningApplication?
    ) -> Bool {
        if frontmost?.bundleIdentifier == browser.bundleID { return true }
        return isSelf(frontmost) && siteCover?.browserID == browser.bundleID
    }

    private func isSelf(_ app: NSRunningApplication?) -> Bool {
        app?.processIdentifier == NSRunningApplication.current.processIdentifier
    }

    /// Takes a site cover down and forgets its clock; a no-op when none is up
    /// and never touches an app cover.
    private func dropSiteCover() {
        siteCover = nil
        cover.hideSite()
    }

    /// The v16 escalation: switch the tab away and say so in the toast.
    private func switchAwayAndAnnounce(
        browser: BrowserScripting.Browser, target: String, neighborBlocked: (String?) -> Bool
    ) {
        switchAway(in: browser, neighborBlocked: neighborBlocked)
        overlay.show(target: target, remainingSeconds: remainingSeconds())
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
