import Foundation

/// v18 escalation ladder for one blocked app. `NSRunningApplication.hide()`
/// is silently ignored for apps in native macOS fullscreen (own Space), so
/// the gentle v16 hide alone fails exactly where distraction is strongest.
/// This is the pure decision of what to try next, given where the ladder
/// stands and whether the app is still visible after the previous attempt.
///
/// v21 adds the Space escape between the un-fullscreen and the cover: the
/// AX rung turned out to fail for real apps even *with* the permission
/// (Catalyst/Electron windows reject `AXFullScreen` writes), and a
/// background app's window is never drawn inside another app's fullscreen
/// Space — so the only reliable way out is to activate the Timer itself and
/// let macOS switch the Space. It runs whenever the app is still in front
/// after the hide/AX attempts, no matter why they failed.
///
/// The ladder never escalates past the overlay and never kills anything.
public enum BlockEscalation {
    /// What has already been attempted for this app in the current run.
    public enum Step: Equatable {
        /// Nothing tried yet (every block event starts here).
        case start
        /// Step 1 — `hide()` was attempted.
        case hideTried
        /// Step 2 — windows were pulled out of fullscreen and hidden again.
        case unfullscreenTried
        /// Step 3 (v21) — the Timer activated and took over the Space.
        case escapeTried
        /// Step 4 — the cover overlay is up.
        case overlayShown

        /// The step an action leads to, i.e. the ladder's memory between the
        /// attempt and its (delayed) visibility verification. `.done` rearms
        /// the ladder, so the next block event starts from scratch.
        public static func after(_ action: Action) -> Step {
            switch action {
            case .hide: return .hideTried
            case .unfullscreenThenHide: return .unfullscreenTried
            case .spaceEscape: return .escapeTried
            case .overlay: return .overlayShown
            case .done: return .start
            }
        }
    }

    public enum Action: Equatable {
        /// Step 1: plain `hide()`, then verify.
        case hide
        /// Step 2: set every fullscreen window's `AXFullScreen` to false and
        /// hide again, then verify. Needs the Accessibility permission.
        case unfullscreenThenHide
        /// Step 3 (v21): put the cover on the Timer's own Space, activate,
        /// and make it key — macOS pulls the user out of the blocked app's
        /// fullscreen Space. Needs no permission at all.
        case spaceEscape
        /// Step 4: show (or keep) the cover overlay — no permission needed.
        case overlay
        /// Nothing to do: the app is out of sight; any cover comes down.
        case done
    }

    /// The next rung. An invisible app is always `.done` (that includes apps
    /// the user hid himself — the caller never records those). Without the
    /// Accessibility permission step 2 is skipped; the escape then follows
    /// straight after the hide, so an unpermitted Timer blocks just as well.
    ///
    /// `appFrontmost` and `escapeAllowed` (the caller's per-app 3 s throttle)
    /// gate the escape only: an app the user already left is not worth a
    /// Space switch, and a throttled one gets the cover instead while the
    /// silent hide attempts continue. Both default to "no escape", which is
    /// exactly the v18 ladder.
    public static func next(
        step: Step, appVisible: Bool, appFrontmost: Bool = false,
        accessibilityGranted: Bool, escapeAllowed: Bool = false
    ) -> Action {
        guard appVisible else { return .done }
        let canEscape = appFrontmost && escapeAllowed
        switch step {
        case .start:
            return .hide
        case .hideTried:
            if accessibilityGranted { return .unfullscreenThenHide }
            return canEscape ? .spaceEscape : .overlay
        case .unfullscreenTried:
            return canEscape ? .spaceEscape : .overlay
        case .escapeTried:
            // The Space is switched; hiding an app that is no longer holding
            // the screen is the cheapest way out — and usually works now.
            return .hide
        case .overlayShown:
            return .overlay
        }
    }
}
