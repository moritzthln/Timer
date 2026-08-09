import AppKit
import TimerCore

/// Enforces the focus block while a focus session runs — gently since v16:
/// apps are hidden (never terminated) and restored when the block ends, and
/// blocked browser tabs stay open while the browser switches away from them.
/// Blocklist mode intervenes on blocklisted apps and browser tabs; allowlist
/// mode (v15) on unlisted regular apps and tabs on unlisted hosts. The mode
/// is consulted per event/poll, so a mid-session mode change applies
/// naturally on the next event.
final class FocusBlockController {
    private let preferences: Preferences
    private let overlay: BlockOverlayController
    private var active = false
    private var pollTimer: Foundation.Timer?
    private var launchObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?
    private var hiddenApps = HiddenAppsRecord()
    /// Bundle ids whose tab-switch scripting failed this activation (Arc
    /// when its Chromium-style commands are rejected); they use the v15
    /// close fallback until the next activation probes again.
    private var tabSwitchUnsupported: Set<String> = []

    init(preferences: Preferences, overlay: BlockOverlayController) {
        self.preferences = preferences
        self.overlay = overlay
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
            restoreHiddenApps()
        }
    }

    /// Unhides every app this controller hid and clears the record. Runs on
    /// every block deactivation and on app quit (prepareForTermination).
    /// Apps the user hid manually were never recorded and stay untouched.
    func restoreHiddenApps() {
        let ids = hiddenApps.drain()
        guard !ids.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, ids.contains(id) {
                _ = app.unhide()
            }
        }
    }

    // MARK: - Apps

    /// Activation sweep over the already-running apps, per the current mode.
    private func sweepRunningApps() {
        switch preferences.blockMode {
        case .blocklist: hideRunningBlockedApps()
        case .allowlist: hideRunningDisallowedApps()
        }
    }

    private func hideRunningBlockedApps() {
        let blockedIDs = Set(preferences.blockedApps.map(\.bundleID))
        guard !blockedIDs.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, blockedIDs.contains(id) {
                hideBlocked(app)
            }
        }
    }

    private func hideRunningDisallowedApps() {
        for app in NSWorkspace.shared.runningApplications where shouldHideInAllowlist(app) {
            hideNotAllowed(app)
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

    private func hideBlocked(_ app: NSRunningApplication) {
        guard hide(app) else { return }
        let name = preferences.blockedApps.first { $0.bundleID == app.bundleIdentifier }?.name
            ?? app.localizedName ?? "App"
        overlay.show(blocked: name)
    }

    private func hideNotAllowed(_ app: NSRunningApplication) {
        guard hide(app) else { return }
        overlay.show(notAllowed: app.localizedName ?? "App")
    }

    /// Gentle intervention: hide and remember what *we* hid. An app that is
    /// already hidden (e.g. by the user) is skipped entirely, and only a
    /// successful hide is recorded — restore never touches anything this
    /// controller did not hide itself. Returns whether to announce.
    private func hide(_ app: NSRunningApplication) -> Bool {
        guard !app.isHidden, app.hide() else { return false }
        if let id = app.bundleIdentifier {
            hiddenApps.add(id)
        }
        return true
    }

    /// Launch/activation handler; reads the mode per event. Activation
    /// matters because hidden apps keep running: clicking one in the Dock
    /// unhides it without a launch event, so it must be hidden again.
    private func handleLaunchOrActivate(_ app: NSRunningApplication) {
        switch preferences.blockMode {
        case .blocklist:
            guard let id = app.bundleIdentifier,
                  preferences.blockedApps.contains(where: { $0.bundleID == id }) else { return }
            hideBlocked(app)
        case .allowlist:
            guard shouldHideInAllowlist(app) else { return }
            hideNotAllowed(app)
        }
    }

    private func startWatching() {
        launchObserver = workspaceObserver(for: NSWorkspace.didLaunchApplicationNotification)
        activateObserver = workspaceObserver(for: NSWorkspace.didActivateApplicationNotification)
        pollTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollBrowsers()
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

    // MARK: - Browsers

    /// Reads the mode per poll tick.
    private func pollBrowsers() {
        guard active else { return }
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
                overlay.show(blocked: matched)
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
            overlay.show(notAllowed: host)
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
