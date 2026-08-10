import Foundation

/// v25 replaces the v18–v21 escalation ladder. The ladder tried one technique
/// per rung, waited for a verdict, and gave up at the end of its chain — which
/// is exactly where the user found it wanting: apps that ignored the first
/// attempt (fullscreen, busy, mid-animation) stayed put. The block now insists
/// instead: a fast loop repeats *every* applicable technique until the app is
/// out of sight, and the poll re-arms the loop for as long as it is not.
///
/// This is the pure per-attempt decision — what the loop is allowed to do at
/// this point, given the live state of the app. The runner supplies the state
/// and performs whatever comes back.
public struct BlockPlan: Equatable {
    /// Set every window's `AXFullScreen` to false. Idempotent and safe on a
    /// windowed app (unlike the keyboard shortcut, which would toggle it *in*).
    public var exitFullscreenViaAX = false
    /// `NSRunningApplication.hide()` — refused while the app owns a fullscreen
    /// Space, which is why the loop keeps coming back.
    public var hide = false
    /// Minimise every window: the fallback for apps that refuse to hide.
    public var minimize = false
    /// Synthetic ⌃⌘F. Only ever for the frontmost app (key events go there)
    /// and only when it is fullscreen — or has been resisting long enough that
    /// fullscreen is the only remaining explanation.
    public var sendExitFullscreenKey = false
    /// Synthetic ⌃←: leave the Space entirely, for apps that ignore ⌃⌘F.
    public var sendSpaceLeftKey = false
    /// Nothing left to do — the app is gone.
    public var stop = false

    public init() {}

    /// The plan for an app that is already out of sight.
    public static let done: BlockPlan = {
        var plan = BlockPlan()
        plan.stop = true
        return plan
    }()

    /// Whether this attempt does anything at all.
    public var isEmpty: Bool {
        !exitFullscreenViaAX && !hide && !minimize
            && !sendExitFullscreenKey && !sendSpaceLeftKey
    }
}

public enum BlockAttempt {
    /// From this attempt on, minimising joins the hide attempts.
    public static let minimizeFrom = 2
    /// From this attempt on, the Space-left shortcut joins in.
    public static let spaceLeftFrom = 6

    /// What to do on this attempt.
    ///
    /// `keyEventAllowed` is the runner's throttle: the exit-fullscreen
    /// animation takes about half a second, and a second shortcut landing
    /// inside it would toggle the app straight back in. Everything else is
    /// idempotent and repeats freely.
    public static func plan(
        attempt: Int,
        visible: Bool,
        frontmost: Bool,
        fullscreen: Bool,
        accessibilityGranted: Bool,
        keyEventAllowed: Bool
    ) -> BlockPlan {
        guard visible else { return .done }
        var plan = BlockPlan()
        plan.hide = true
        plan.exitFullscreenViaAX = accessibilityGranted
        plan.minimize = accessibilityGranted && attempt >= minimizeFrom
        // Both shortcuts are toggles, so they may only ever fire against an
        // app that *is* fullscreen right now. An earlier version also sent
        // them on suspicion (a frontmost app still refusing to hide), which
        // put apps that had just left fullscreen straight back in — the user
        // saw "kommt aus dem Vollbild raus, wird aber nicht ausgeblendet".
        // Detection is reliable whenever the shortcuts can work at all: both
        // need the Accessibility permission.
        guard frontmost, keyEventAllowed, fullscreen else { return plan }
        plan.sendExitFullscreenKey = true
        plan.sendSpaceLeftKey = attempt >= spaceLeftFrom
        return plan
    }
}
