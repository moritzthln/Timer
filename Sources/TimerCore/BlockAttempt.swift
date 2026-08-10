import Foundation

/// The pure part of the block's decision for one app.
///
/// v25.3 splits the work in two, because macOS forces it: an app that is not
/// active exposes **no** Accessibility windows, so nothing can un-fullscreen
/// it from the outside (measured: Telegram and WhatsApp, both sitting in
/// fullscreen, both reporting zero AX windows). Only the app that has the
/// screen can be taken out of fullscreen — therefore the block first walks the
/// fullscreen apps one by one and dissolves them, and only then hides
/// everything. Hiding first is what created the trap the user kept hitting:
/// `hide()` succeeds on a fullscreen app but leaves its Space and window
/// behind, and once hidden the app is unreachable for good.
///
/// This type decides which of the two an app needs; the sweep itself lives in
/// `AppBlockEnforcer`, since it is pure AppKit choreography.
public struct BlockPlan: Equatable {
    /// Bring a hidden app back: its fullscreen window survived a hide and can
    /// only be reached while the app is visible.
    public var unhide = false
    /// Hand the app to the fullscreen sweep — it takes the screen, so hiding
    /// it now would strand its Space.
    public var sweepFullscreen = false
    /// `NSRunningApplication.hide()`.
    public var hide = false
    /// Minimise every window: the fallback for apps that refuse to hide.
    public var minimize = false
    /// Nothing left to do — the app is hidden and holds no screen.
    public var stop = false

    public init() {}

    /// The plan for an app that is properly out of the way.
    public static let done: BlockPlan = {
        var plan = BlockPlan()
        plan.stop = true
        return plan
    }()

    /// Whether this attempt does anything at all.
    public var isEmpty: Bool { !unhide && !sweepFullscreen && !hide && !minimize }
}

public enum BlockAttempt {
    /// From this attempt on, minimising joins the hide attempts.
    public static let minimizeFrom = 2

    /// What this app needs next.
    ///
    /// `occupiesScreen` is "the app owns a window the size of a whole screen",
    /// answered by Accessibility where it can be and by the window server
    /// otherwise — the latter being the only source that still sees the
    /// windows of an inactive fullscreen app.
    public static func plan(
        attempt: Int,
        hidden: Bool,
        occupiesScreen: Bool,
        accessibilityGranted: Bool
    ) -> BlockPlan {
        var plan = BlockPlan()
        if hidden {
            // Hidden and windowed is the goal state. Hidden *and* still
            // holding a screen is the trap: undo the hide, so the window
            // becomes reachable again.
            guard occupiesScreen else { return .done }
            plan.unhide = true
            return plan
        }
        guard !occupiesScreen else {
            plan.sweepFullscreen = true
            return plan
        }
        plan.hide = true
        plan.minimize = accessibilityGranted && attempt >= minimizeFrom
        return plan
    }
}
