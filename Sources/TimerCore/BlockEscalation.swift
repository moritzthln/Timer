import Foundation

/// v18 escalation ladder for one blocked app. `NSRunningApplication.hide()`
/// is silently ignored for apps in native macOS fullscreen (own Space), so
/// the gentle v16 hide alone fails exactly where distraction is strongest.
/// This is the pure decision of what to try next, given where the ladder
/// stands and whether the app is still visible after the previous attempt.
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
        /// Step 3 — the cover overlay is up.
        case overlayShown

        /// The step an action leads to, i.e. the ladder's memory between the
        /// attempt and its (delayed) visibility verification. `.done` rearms
        /// the ladder, so the next block event starts from scratch.
        public static func after(_ action: Action) -> Step {
            switch action {
            case .hide: return .hideTried
            case .unfullscreenThenHide: return .unfullscreenTried
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
        /// Step 3: show (or keep) the cover overlay — no permission needed.
        case overlay
        /// Nothing to do: the app is out of sight; any cover comes down.
        case done
    }

    /// The next rung. An invisible app is always `.done` (that includes apps
    /// the user hid himself — the caller never records those). Without the
    /// Accessibility permission step 2 is skipped entirely, so a fullscreen
    /// app goes straight to the overlay instead of prompting again and again.
    public static func next(
        step: Step, appVisible: Bool, accessibilityGranted: Bool
    ) -> Action {
        guard appVisible else { return .done }
        switch step {
        case .start:
            return .hide
        case .hideTried:
            return accessibilityGranted ? .unfullscreenThenHide : .overlay
        case .unfullscreenTried, .overlayShown:
            return .overlay
        }
    }
}
