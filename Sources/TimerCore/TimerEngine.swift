import Foundation
import Combine

public final class TimerEngine: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case running(endDate: Date, total: TimeInterval)
        case paused(remaining: TimeInterval, total: TimeInterval)
        case finished
    }

    @Published public private(set) var phase: Phase = .idle

    /// Fired exactly once per running→finished transition (opens popover, plays sound).
    public var onFinish: (() -> Void)?

    private let preferences: Preferences
    private let now: () -> Date
    private var ticker: Foundation.Timer?

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
        case .running(let endDate, _):
            return max(0, Int(endDate.timeIntervalSince(now()).rounded(.up)))
        case .paused(let remaining, _):
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
        case .running(let endDate, let total):
            guard total > 0 else { return 1 }
            let remaining = max(0, endDate.timeIntervalSince(now()))
            return min(1, max(0, 1 - remaining / total))
        case .paused(let remaining, let total):
            guard total > 0 else { return 1 }
            return min(1, max(0, 1 - remaining / total))
        case .finished:
            return 1
        }
    }

    public var endDate: Date? {
        if case .running(let endDate, _) = phase { return endDate }
        return nil
    }

    public var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    // MARK: - Actions

    public func start(minutes: Int) {
        let clamped = min(720, max(1, minutes))
        preferences.lastMinutes = clamped
        let total = TimeInterval(clamped * 60)
        let end = now().addingTimeInterval(total)
        phase = .running(endDate: end, total: total)
        preferences.persistRunning(endDate: end, total: total)
        startTicker()
    }

    public func pause() {
        guard case .running(let endDate, let total) = phase else { return }
        let remaining = max(0, endDate.timeIntervalSince(now()))
        phase = .paused(remaining: remaining, total: total)
        preferences.clearRunning()
        stopTicker()
    }

    public func resume() {
        guard case .paused(let remaining, let total) = phase else { return }
        let end = now().addingTimeInterval(remaining)
        phase = .running(endDate: end, total: total)
        preferences.persistRunning(endDate: end, total: total)
        startTicker()
    }

    public func stop() {
        phase = .idle
        preferences.clearRunning()
        stopTicker()
    }

    public func dismissFinished() {
        guard case .finished = phase else { return }
        phase = .idle
    }

    /// Advances state. Called every 0.5 s by the ticker; tests call it directly.
    public func tick() {
        guard case .running(let endDate, _) = phase else { return }
        if now() >= endDate {
            phase = .finished
            preferences.clearRunning()
            stopTicker()
            onFinish?()
        } else {
            // Phase unchanged but derived values moved; notify observers.
            objectWillChange.send()
        }
    }

    // MARK: - Private

    private func restore() {
        guard let run = preferences.persistedRun else { return }
        if run.endDate > now() {
            phase = .running(endDate: run.endDate, total: run.total)
            startTicker()
        } else {
            // Expired while the app was not running: finished state, no sound
            // (onFinish is not wired yet at init time — per spec).
            preferences.clearRunning()
            phase = .finished
        }
    }

    private func startTicker() {
        stopTicker()
        let timer = Foundation.Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
