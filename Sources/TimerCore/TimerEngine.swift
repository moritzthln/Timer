import Foundation
import Combine

public enum PomodoroPhase: Equatable { case focus, shortBreak, longBreak }

public enum SessionKind: Equatable {
    case single
    case pomodoro(phase: PomodoroPhase, round: Int) // round is 1-based
}

public final class TimerEngine: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case running(endDate: Date, total: TimeInterval, kind: SessionKind)
        case paused(remaining: TimeInterval, total: TimeInterval, kind: SessionKind)
        case finished
    }

    @Published public private(set) var phase: Phase = .idle

    /// Fired exactly once per running→finished transition (opens popover, plays sound).
    public var onFinish: (() -> Void)?

    /// Fired once per automatic pomodoro phase transition (chime + popover).
    /// Not fired for user-initiated skips or restores.
    public var onPhaseChange: ((SessionKind) -> Void)?

    /// Fired whenever a focus segment (single timer or pomodoro focus phase)
    /// ends: pause, stop, finish, phase advance, or skip. Interval is clamped
    /// to the phase's end date.
    public var onFocusSegmentEnded: (((start: Date, end: Date)) -> Void)?

    private let preferences: Preferences
    private let now: () -> Date
    private var ticker: Foundation.Timer?
    private var activeConfig: PomodoroConfig?
    private var focusSegmentStart: Date?

    /// Start of the currently open focus segment (running focus work only);
    /// nil while idle, paused, finished, or in a break. Lets the activity
    /// views count the live session before it is written to the focus log.
    public var activeFocusStart: Date? { focusSegmentStart }

    public init(preferences: Preferences, now: @escaping () -> Date = { Date() }) {
        self.preferences = preferences
        self.now = now
        restore()
    }

    // MARK: - Derived state

    public var remainingSeconds: Int {
        switch phase {
        case .idle:
            return preferences.lastMinutes * 60
        case .running(let endDate, _, _):
            return max(0, Int(endDate.timeIntervalSince(now()).rounded(.up)))
        case .paused(let remaining, _, _):
            return max(0, Int(remaining.rounded(.up)))
        case .finished:
            return 0
        }
    }

    /// Elapsed fraction 0...1 for the progress bar.
    public var progress: Double {
        switch phase {
        case .idle:
            return 0
        case .running(let endDate, let total, _):
            guard total > 0 else { return 1 }
            let remaining = max(0, endDate.timeIntervalSince(now()))
            return min(1, max(0, 1 - remaining / total))
        case .paused(let remaining, let total, _):
            guard total > 0 else { return 1 }
            return min(1, max(0, 1 - remaining / total))
        case .finished:
            return 1
        }
    }

    public var endDate: Date? {
        if case .running(let endDate, _, _) = phase { return endDate }
        return nil
    }

    public var currentKind: SessionKind? {
        switch phase {
        case .running(_, _, let kind), .paused(_, _, let kind): return kind
        case .idle, .finished: return nil
        }
    }

    public var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    // MARK: - Actions

    /// What this session is dedicated to — free text, empty when the user
    /// did not bother. Display only: it is never written to the statistics,
    /// it just travels with the session (including across a relaunch) and is
    /// dropped when the session ends.
    @Published public private(set) var label = ""

    public func start(minutes: Int, label: String = "") {
        self.label = label
        let clamped = min(720, max(1, minutes))
        preferences.lastMinutes = clamped
        activeConfig = nil
        let total = TimeInterval(clamped * 60)
        let end = now().addingTimeInterval(total)
        phase = .running(endDate: end, total: total, kind: .single)
        preferences.persistRun(PersistedRun(endDate: end, total: total, kind: .single, config: nil, label: label))
        startTicker()
        openFocusSegmentIfNeeded(kind: .single, at: now())
    }

    public func startPomodoro(config: PomodoroConfig, label: String = "") {
        self.label = label
        activeConfig = config
        let total = config.duration(of: .focus)
        let kind = SessionKind.pomodoro(phase: .focus, round: 1)
        let end = now().addingTimeInterval(total)
        phase = .running(endDate: end, total: total, kind: kind)
        preferences.persistRun(PersistedRun(endDate: end, total: total, kind: kind, config: config, label: label))
        startTicker()
        openFocusSegmentIfNeeded(kind: kind, at: now())
    }

    public func skip() {
        guard let kind = currentKind, case .pomodoro = kind,
              let config = activeConfig else { return }
        closeFocusSegment(cappedAt: nil)
        let next = config.next(after: kind)
        startPhase(next, at: now(), config: config)
    }

    public func pause() {
        guard case .running(let endDate, let total, let kind) = phase else { return }
        closeFocusSegment(cappedAt: endDate)
        let remaining = max(0, endDate.timeIntervalSince(now()))
        phase = .paused(remaining: remaining, total: total, kind: kind)
        preferences.clearRunning()
        stopTicker()
    }

    public func resume() {
        guard case .paused(let remaining, let total, let kind) = phase else { return }
        let end = now().addingTimeInterval(remaining)
        phase = .running(endDate: end, total: total, kind: kind)
        preferences.persistRun(PersistedRun(endDate: end, total: total, kind: kind, config: activeConfig, label: label))
        startTicker()
        openFocusSegmentIfNeeded(kind: kind, at: now())
    }

    public func stop() {
        if case .running(let endDate, _, _) = phase {
            closeFocusSegment(cappedAt: endDate)
        }
        phase = .idle
        activeConfig = nil
        label = ""
        preferences.clearRunning()
        stopTicker()
    }

    public func dismissFinished() {
        guard case .finished = phase else { return }
        phase = .idle
    }

    /// Grows the current phase by `minutes` — single timers and the current
    /// pomodoro phase alike (following phases keep their configured length).
    /// Running: endDate and total grow and the run is re-persisted; paused:
    /// remaining and total grow (paused runs stay unpersisted, matching
    /// `pause()`). The total is clamped to 720 minutes — the added time
    /// shrinks accordingly. No-op on idle, finished, and at the cap.
    public func extend(minutes: Int) {
        guard minutes > 0 else { return }
        switch phase {
        case .running(let endDate, let total, let kind):
            guard let added = Self.clampedExtension(total: total, minutes: minutes) else { return }
            let end = endDate.addingTimeInterval(added)
            phase = .running(endDate: end, total: total + added, kind: kind)
            preferences.persistRun(
                PersistedRun(endDate: end, total: total + added, kind: kind, config: activeConfig, label: label)
            )
        case .paused(let remaining, let total, let kind):
            guard let added = Self.clampedExtension(total: total, minutes: minutes) else { return }
            phase = .paused(remaining: remaining + added, total: total + added, kind: kind)
        case .idle, .finished:
            return
        }
    }

    /// Seconds to actually add so the total never exceeds 720 min; nil when
    /// already at the cap.
    private static func clampedExtension(total: TimeInterval, minutes: Int) -> TimeInterval? {
        let added = min(TimeInterval(720 * 60), total + TimeInterval(minutes * 60)) - total
        return added > 0 ? added : nil
    }

    /// Advances state. Called every 0.5 s by the ticker; tests call it directly.
    public func tick() {
        guard case .running(let endDate, _, let kind) = phase else { return }
        if now() >= endDate {
            switch kind {
            case .single:
                closeFocusSegment(cappedAt: endDate)
                phase = .finished
                preferences.clearRunning()
                stopTicker()
                onFinish?()
            case .pomodoro:
                guard let config = activeConfig else {
                    stop()
                    return
                }
                closeFocusSegment(cappedAt: endDate)
                let landed = advancePomodoro(after: kind, boundary: endDate, config: config)
                onPhaseChange?(landed)
            }
        } else {
            // Phase unchanged but derived values moved; notify observers.
            objectWillChange.send()
        }
    }

    // MARK: - Private

    private static func isFocusKind(_ kind: SessionKind) -> Bool {
        switch kind {
        case .single: return true
        case .pomodoro(let phase, _): return phase == .focus
        }
    }

    /// Called on every transition that leaves a running state.
    /// `boundary` caps the segment (phase end date); pass nil to cap at now().
    private func closeFocusSegment(cappedAt boundary: Date?) {
        guard let start = focusSegmentStart else { return }
        focusSegmentStart = nil
        let rawEnd = boundary.map { min($0, now()) } ?? now()
        let end = max(rawEnd, start)
        guard end > start else { return }
        onFocusSegmentEnded?((start: start, end: end))
    }

    private func openFocusSegmentIfNeeded(kind: SessionKind, at date: Date) {
        focusSegmentStart = Self.isFocusKind(kind) ? date : nil
    }

    /// Puts the engine into `kind` running from `start` (end = start + duration).
    private func startPhase(_ kind: SessionKind, at start: Date, config: PomodoroConfig) {
        guard case .pomodoro(let phase, _) = kind else { return }
        let total = config.duration(of: phase)
        let end = start.addingTimeInterval(total)
        self.phase = .running(endDate: end, total: total, kind: kind)
        preferences.persistRun(PersistedRun(endDate: end, total: total, kind: kind, config: config, label: label))
        startTicker()
        openFocusSegmentIfNeeded(kind: kind, at: start)
    }

    /// Advances past `boundary` into the phase containing `now()`, fast-forwarding
    /// any fully elapsed phases. Returns the landed kind.
    @discardableResult
    private func advancePomodoro(after kind: SessionKind, boundary: Date, config: PomodoroConfig) -> SessionKind {
        var nextKind = config.next(after: kind)
        var start = boundary
        while true {
            guard case .pomodoro(let phase, _) = nextKind else { break }
            let end = start.addingTimeInterval(config.duration(of: phase))
            if end > now() { break }
            // Fully skipped-over focus phases still count as focus time.
            if phase == .focus {
                onFocusSegmentEnded?((start: start, end: end))
            }
            start = end
            nextKind = config.next(after: nextKind)
        }
        startPhase(nextKind, at: start, config: config)
        return nextKind
    }

    private func restore() {
        guard let run = preferences.persistedRun else { return }
        activeConfig = run.config
        label = run.label
        if run.endDate > now() {
            phase = .running(endDate: run.endDate, total: run.total, kind: run.kind)
            startTicker()
            // Counting resumes from launch time (time while the app was
            // closed is not credited).
            openFocusSegmentIfNeeded(kind: run.kind, at: now())
            return
        }
        switch run.kind {
        case .single:
            preferences.clearRunning()
            phase = .finished
        case .pomodoro:
            guard let config = run.config else {
                preferences.clearRunning()
                return
            }
            // Catch up silently (onPhaseChange is not wired during init).
            let landed = advancePomodoro(after: run.kind, boundary: run.endDate, config: config)
            // Same rule as the direct restore: no credit for app-closed time.
            openFocusSegmentIfNeeded(kind: landed, at: now())
        }
    }

    private func startTicker() {
        stopTicker()
        let timer = Foundation.Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.1 // v8 energy audit: let the OS coalesce wakeups
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
