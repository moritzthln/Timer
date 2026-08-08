import AppKit
import TimerCore

/// Enforces the focus block while a focus session runs. Blocklist mode
/// terminates blocklisted apps and closes blocklisted browser tabs;
/// allowlist mode (v15) terminates unlisted regular apps and closes tabs on
/// unlisted hosts. The mode is consulted per event/poll, so a mid-session
/// mode change applies naturally on the next event.
final class FocusBlockController {
    private let preferences: Preferences
    private let overlay: BlockOverlayController
    private var active = false
    private var pollTimer: Foundation.Timer?
    private var launchObserver: NSObjectProtocol?

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
            sweepRunningApps()
            startWatching()
        } else {
            stopWatching()
        }
    }

    // MARK: - Apps

    /// Activation sweep over the already-running apps, per the current mode.
    private func sweepRunningApps() {
        switch preferences.blockMode {
        case .blocklist: terminateRunningBlockedApps()
        case .allowlist: terminateRunningDisallowedApps()
        }
    }

    private func terminateRunningBlockedApps() {
        let blockedIDs = Set(preferences.blockedApps.map(\.bundleID))
        guard !blockedIDs.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, blockedIDs.contains(id) {
                terminateBlocked(app)
            }
        }
    }

    private func terminateRunningDisallowedApps() {
        for app in NSWorkspace.shared.runningApplications where shouldTerminateInAllowlist(app) {
            terminateNotAllowed(app)
        }
    }

    /// Allowlist app arm: regular user apps only — the pure rule covers the
    /// allowed set, the essential set, and the empty-list guard. The running
    /// Timer binary is additionally protected via its live bundle ID (covers
    /// dev builds whose ID differs from the packaged one).
    private func shouldTerminateInAllowlist(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return false }
        let essential = AllowlistRules.essentialBundleIDs.union(
            [Bundle.main.bundleIdentifier].compactMap { $0 }
        )
        return AllowlistRules.shouldTerminate(
            bundleID: id,
            allowed: Set(preferences.allowedApps.map(\.bundleID)),
            essential: essential
        )
    }

    private func terminateBlocked(_ app: NSRunningApplication) {
        let name = preferences.blockedApps.first { $0.bundleID == app.bundleIdentifier }?.name
            ?? app.localizedName ?? "App"
        app.terminate()
        overlay.show(blocked: name)
    }

    private func terminateNotAllowed(_ app: NSRunningApplication) {
        let name = app.localizedName ?? "App"
        app.terminate()
        overlay.show(notAllowed: name)
    }

    /// Launch handler; reads the mode per event.
    private func handleLaunch(_ app: NSRunningApplication) {
        switch preferences.blockMode {
        case .blocklist:
            guard let id = app.bundleIdentifier,
                  preferences.blockedApps.contains(where: { $0.bundleID == id }) else { return }
            terminateBlocked(app)
        case .allowlist:
            guard shouldTerminateInAllowlist(app) else { return }
            terminateNotAllowed(app)
        }
    }

    private func startWatching() {
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self, self.active,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self.handleLaunch(app)
        }
        pollTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollBrowsers()
        }
        pollTimer?.tolerance = 0.5 // v8 energy audit
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    private func stopWatching() {
        if let launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(launchObserver)
        }
        launchObserver = nil
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
        for browser in runningSupportedBrowsers() {
            guard let urlString = BrowserScripting.run(browser.readURL),
                  let host = URL(string: urlString)?.host else { continue }
            let matched = domains.first { FocusBlockRules.domainMatches(host: host, entry: $0) }
            if let matched {
                _ = BrowserScripting.run(browser.closeTab)
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
            _ = BrowserScripting.run(browser.closeTab)
            overlay.show(notAllowed: host)
        }
    }

    private func runningSupportedBrowsers() -> [BrowserScripting.Browser] {
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return BrowserScripting.supported.filter { runningIDs.contains($0.bundleID) }
    }
}
