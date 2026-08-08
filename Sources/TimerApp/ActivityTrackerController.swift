import AppKit
import CoreGraphics
import TimerCore

/// Records presence, frontmost-app, and browser-domain segments.
final class ActivityTrackerController {
    private let store: ActivityStore
    private let preferences: Preferences

    private var present = false
    private var screenLocked = false
    private var asleep = false

    private var openPresence: ActivitySegment?
    private var openApp: ActivitySegment?
    private var openSite: ActivitySegment?

    private var pollTimer: Foundation.Timer?
    private var heartbeat: Foundation.Timer?
    private var observers: [Any] = []

    init(store: ActivityStore, preferences: Preferences) {
        self.store = store
        self.preferences = preferences
        subscribe()
        startTimers()
        evaluatePresence()
    }

    // MARK: - Signals

    private func subscribe() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontmostChanged(to: app)
        })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.asleep = true
            self?.evaluatePresence()
        })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.asleep = false
            self?.evaluatePresence()
        })
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.screenLocked = true
            self?.evaluatePresence()
        })
        observers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.screenLocked = false
            self?.evaluatePresence()
        })
    }

    private func startTimers() {
        let poll = Foundation.Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.evaluatePresence()
            self?.pollBrowserTab()
        }
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll

        let beat = Foundation.Timer(timeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.persistOpenSegments()
        }
        RunLoop.main.add(beat, forMode: .common)
        heartbeat = beat
    }

    // MARK: - Presence

    private static func lastInputAge() -> TimeInterval {
        let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .scrollWheel]
        return types.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.min() ?? .infinity
    }

    /// Reevaluates presence; on idle-triggered absence the presence segment
    /// is backdated to the last input.
    private func evaluatePresence() {
        let age = Self.lastInputAge()
        let threshold = TimeInterval(preferences.idleThresholdMinutes * 60)
        let nowPresent = PresenceRules.isPresent(
            lastInputAge: age, thresholdSeconds: threshold,
            screenLocked: screenLocked, asleep: asleep,
            paused: preferences.trackingPaused
        )
        guard nowPresent != present else { return }
        present = nowPresent
        if nowPresent {
            let now = Date()
            openPresence = ActivitySegment(kind: .presence, start: now, end: now)
            frontmostChanged(to: NSWorkspace.shared.frontmostApplication)
        } else {
            let idleTriggered = age > threshold && !screenLocked && !asleep
            let cutoff = idleTriggered ? Date().addingTimeInterval(-age) : Date()
            closeAll(at: cutoff)
        }
    }

    // MARK: - App segments

    private func frontmostChanged(to app: NSRunningApplication?) {
        let now = Date()
        closeSegment(&openApp, at: now)
        closeSegment(&openSite, at: now)
        guard present, let app, let bundleID = app.bundleIdentifier else { return }
        openApp = ActivitySegment(
            kind: .app(bundleID: bundleID, name: app.localizedName ?? bundleID),
            start: now, end: now
        )
    }

    // MARK: - Browser segments

    private func pollBrowserTab() {
        guard present else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let browser = BrowserScripting.browser(forBundleID: frontmost) else {
            closeSegment(&openSite, at: Date())
            return
        }
        let now = Date()
        guard let urlString = BrowserScripting.run(browser.readURL),
              let host = URL(string: urlString)?.host else {
            closeSegment(&openSite, at: now)
            return
        }
        let domain = ActivitySegment.normalizeHost(host)
        if case .site(let openDomain, _)? = openSite?.kind, openDomain == domain {
            return // same site, keep the segment growing
        }
        closeSegment(&openSite, at: now)
        openSite = ActivitySegment(
            kind: .site(domain: domain, browserBundleID: browser.bundleID),
            start: now, end: now
        )
    }

    // MARK: - Segment lifecycle

    private func closeSegment(_ segment: inout ActivitySegment?, at date: Date) {
        guard var open = segment else { return }
        segment = nil
        open.end = max(date, open.start)
        store.upsert(open)
    }

    private func closeAll(at date: Date) {
        closeSegment(&openSite, at: date)
        closeSegment(&openApp, at: date)
        closeSegment(&openPresence, at: date)
    }

    /// Heartbeat: re-persist open segments so a crash loses ≤ 60 s.
    private func persistOpenSegments() {
        let now = Date()
        for var open in [openPresence, openApp, openSite].compactMap({ $0 }) {
            open.end = now
            store.upsert(open)
        }
        openPresence?.end = now
        openApp?.end = now
        openSite?.end = now
    }

    /// Final flush on app termination.
    func flush() {
        closeAll(at: Date())
    }

    /// Persists open segments immediately without closing them, so the
    /// quality recorder reads up-to-date data (otherwise the last ≤ 60 s
    /// of the open app segment would be missing from the calculation).
    func flushNow() {
        persistOpenSegments()
    }
}
