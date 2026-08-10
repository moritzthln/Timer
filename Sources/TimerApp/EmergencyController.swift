import Combine
import Foundation
import TimerCore

/// v24: owns the emergency session — the persisted end date, the one-second
/// ticker that drives the popover banner and the menu bar, and the automatic
/// end. Deliberately not part of `TimerEngine`: an emergency session is no
/// timer, it coexists with one (and with pomodoro rounds) untouched.
final class EmergencyController: ObservableObject {
    /// Non-nil exactly while a session runs, so the banner appears and
    /// disappears with it.
    @Published private(set) var session: EmergencySession?

    /// Whole seconds left, refreshed every tick (0 while nothing runs).
    @Published private(set) var remainingSeconds = 0

    /// The popover's inline start panel. Published because the status item has
    /// to hand the popover its new size when the panel opens or closes.
    @Published var isConfiguring = false

    /// Fired once when a session runs out on its own — never on cancel. The
    /// status bar plays the chime there.
    var onTimeout: (() -> Void)?

    private let preferences: Preferences
    private var ticker: Foundation.Timer?

    var isActive: Bool { session != nil }

    /// What the start panel offers: the last used duration.
    var suggestedMinutes: Int { preferences.emergencyMinutes }

    init(preferences: Preferences) {
        self.preferences = preferences
        // A session that outlived a relaunch continues; one that elapsed while
        // the app was gone is cleared by the read itself.
        adopt(preferences.emergencySession())
    }

    /// The single start path — the model clamps the duration (1...60).
    func start(minutes: Int) {
        adopt(preferences.startEmergency(minutes: minutes))
        isConfiguring = false
    }

    /// The only cancel path is the popover's ten-second hold; the timeout
    /// below shares it. Everything the block hid is restored by the block
    /// controller, which reconciles as soon as the session is gone.
    func cancel() {
        preferences.endEmergency()
        adopt(nil)
    }

    private func adopt(_ newSession: EmergencySession?) {
        session = newSession
        remainingSeconds = EmergencyMode.remainingSeconds(session: newSession)
        if newSession == nil {
            stopTicker()
        } else {
            startTicker()
        }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.1 // v8 energy audit: the banner tolerates a nudge
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    /// Wall-clock driven like every other countdown here: the tick only reads
    /// the end date, so a slept-through session is over on the first tick
    /// after the wake instead of running on for the missed seconds.
    private func tick() {
        guard let session else {
            stopTicker()
            return
        }
        remainingSeconds = EmergencyMode.remainingSeconds(session: session)
        guard !EmergencyMode.isActive(session: session) else { return }
        preferences.endEmergency()
        adopt(nil)
        onTimeout?()
    }
}
