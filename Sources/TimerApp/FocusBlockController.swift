import AppKit
import TimerCore

/// Enforces the focus block: terminates blocklisted apps and closes
/// blocklisted browser tabs while a focus session runs.
final class FocusBlockController {
    private let preferences: Preferences
    private let overlay: BlockOverlayController
    private var active = false
    private var pollTimer: Foundation.Timer?
    private var launchObserver: NSObjectProtocol?

    private struct Browser {
        let bundleID: String
        let readURL: String
        let closeTab: String
    }

    private static let browsers: [Browser] = [
        Browser(
            bundleID: "com.apple.Safari",
            readURL: "tell application \"Safari\" to return URL of current tab of front window",
            closeTab: "tell application \"Safari\" to close current tab of front window"
        ),
        Browser(
            bundleID: "com.google.Chrome",
            readURL: "tell application \"Google Chrome\" to return URL of active tab of front window",
            closeTab: "tell application \"Google Chrome\" to close active tab of front window"
        ),
        Browser(
            bundleID: "company.thebrowser.Browser",
            readURL: "tell application \"Arc\" to return URL of active tab of front window",
            closeTab: "tell application \"Arc\" to close active tab of front window"
        ),
    ]

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
            terminateRunningBlockedApps()
            startWatching()
        } else {
            stopWatching()
        }
    }

    // MARK: - Apps

    private func terminateRunningBlockedApps() {
        let blockedIDs = Set(preferences.blockedApps.map(\.bundleID))
        guard !blockedIDs.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, blockedIDs.contains(id) {
                terminate(app)
            }
        }
    }

    private func terminate(_ app: NSRunningApplication) {
        let name = preferences.blockedApps.first { $0.bundleID == app.bundleIdentifier }?.name
            ?? app.localizedName ?? "App"
        app.terminate()
        overlay.show(blocked: name)
    }

    private func startWatching() {
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self, self.active,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier,
                  self.preferences.blockedApps.contains(where: { $0.bundleID == id }) else { return }
            self.terminate(app)
        }
        pollTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollBrowsers()
        }
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

    private func pollBrowsers() {
        let domains = preferences.blockedDomains
        guard active, !domains.isEmpty else { return }
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for browser in Self.browsers where runningIDs.contains(browser.bundleID) {
            guard let urlString = runAppleScript(browser.readURL),
                  let host = URL(string: urlString)?.host else { continue }
            let matched = domains.first { FocusBlockRules.domainMatches(host: host, entry: $0) }
            if let matched {
                _ = runAppleScript(browser.closeTab)
                overlay.show(blocked: matched)
            }
        }
    }

    /// Returns the string result, or nil on any scripting/permission error.
    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result.stringValue
    }
}
