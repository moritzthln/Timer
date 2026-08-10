import Foundation

/// v25 replaces the v18–v21 escalation ladder. The ladder tried one technique
/// per rung, waited for a verdict, and gave up at the end of its chain — which
/// is exactly where the user found it wanting: apps that ignored the first
/// attempt (fullscreen, busy, mid-animation) stayed put. The block now insists
/// instead: a fast loop repeats every applicable technique until the app is
/// out of sight, and the poll re-arms the loop for as long as it is not.
///
/// v25.2 fixes the order, which was the real reason "Vollbild-Apps bleiben im
/// Vollbild": `hide()` **succeeds** on a fullscreen app, but only takes the
/// app off the current screen — its fullscreen Space keeps the window. The app
/// then reads as hidden (so the loop stopped) while its Space still showed it
/// fullscreen, and a hidden app exposes no AX windows, so nothing could
/// un-fullscreen it any more. Hiding is therefore forbidden while an app is
/// fullscreen, and an app already stuck in that state is unhidden once so it
/// can be taken apart properly.
public struct BlockPlan: Equatable {
    /// Bring a hidden app back, because its fullscreen window survived the
    /// hide and can only be reached while the app is visible.
    public var unhide = false
    /// Set every window's `AXFullScreen` to false. Idempotent and safe on a
    /// windowed app (unlike the keyboard shortcut, which would toggle it *in*).
    public var exitFullscreenViaAX = false
    /// Synthetic ⌃⌘F. Only ever for the frontmost app (key events go there)
    /// and only while it really is fullscreen.
    public var sendExitFullscreenKey = false
    /// Synthetic ⌃←: leave the Space entirely, for apps that ignore ⌃⌘F.
    public var sendSpaceLeftKey = false
    /// Bring the app forward so the keyboard shortcuts can reach it at all —
    /// the last resort for a fullscreen app that rejects the AX write.
    public var activate = false
    /// `NSRunningApplication.hide()`. Never while the app is fullscreen.
    public var hide = false
    /// Minimise every window: the fallback for apps that refuse to hide.
    public var minimize = false
    /// Nothing left to do — the app is hidden and owns no fullscreen window.
    public var stop = false

    public init() {}

    /// The plan for an app that is properly out of the way.
    public static let done: BlockPlan = {
        var plan = BlockPlan()
        plan.stop = true
        return plan
    }()

    /// Whether this attempt does anything at all.
    public var isEmpty: Bool {
        !unhide && !exitFullscreenViaAX && !sendExitFullscreenKey
            && !sendSpaceLeftKey && !activate && !hide && !minimize
    }
}

public enum BlockAttempt {
    /// From this attempt on, minimising joins the hide attempts.
    public static let minimizeFrom = 2
    /// From this attempt on, the Space-left shortcut joins in.
    public static let spaceLeftFrom = 6
    /// From this attempt on (~1.6 s of failing gently), a fullscreen app that
    /// is not in front is brought forward, because the keyboard shortcuts are
    /// the only thing left that can reach it. Deliberately late: it is the one
    /// technique the user actually sees.
    public static let activateFrom = 8

    /// What to do on this attempt.
    ///
    /// `keyEventAllowed` is the runner's throttle: the exit-fullscreen
    /// animation takes about half a second, and a second shortcut landing
    /// inside it would toggle the app straight back in. `escortAllowed` is the
    /// runner's "only one app may be brought forward at a time" gate.
    public static func plan(
        attempt: Int,
        hidden: Bool,
        fullscreen: Bool,
        frontmost: Bool,
        accessibilityGranted: Bool,
        keyEventAllowed: Bool,
        escortAllowed: Bool = false
    ) -> BlockPlan {
        var plan = BlockPlan()
        if hidden {
            // Hidden and windowed is the goal state. Hidden *and* fullscreen
            // is the trap: undo the hide so the window becomes reachable.
            guard fullscreen else { return .done }
            plan.unhide = true
            return plan
        }
        guard fullscreen else {
            plan.hide = true
            plan.minimize = accessibilityGranted && attempt >= minimizeFrom
            return plan
        }
        return fullscreenPlan(
            attempt: attempt, frontmost: frontmost,
            accessibilityGranted: accessibilityGranted,
            keyEventAllowed: keyEventAllowed, escortAllowed: escortAllowed
        )
    }

    /// A visible fullscreen app: get it out of fullscreen, and do *not* hide
    /// it on the way — that is what left the window behind on its Space.
    private static func fullscreenPlan(
        attempt: Int,
        frontmost: Bool,
        accessibilityGranted: Bool,
        keyEventAllowed: Bool,
        escortAllowed: Bool
    ) -> BlockPlan {
        var plan = BlockPlan()
        plan.exitFullscreenViaAX = accessibilityGranted
        if frontmost, keyEventAllowed {
            plan.sendExitFullscreenKey = true
            plan.sendSpaceLeftKey = attempt >= spaceLeftFrom
        }
        if !frontmost, escortAllowed, attempt >= activateFrom {
            plan.activate = true
        }
        // Without the permission and without being in front there is no way to
        // leave fullscreen at all — then hiding is better than nothing, even
        // though the Space survives it.
        if !accessibilityGranted, !frontmost, !plan.activate {
            plan.hide = true
        }
        return plan
    }
}
