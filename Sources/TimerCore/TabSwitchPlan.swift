import Foundation

/// v16 gentle tab blocking: instead of closing a blocked tab, the browser is
/// switched to another tab and the blocked one stays open in the background.
/// This is the pure decision — where to switch to, given the front window's
/// tab geometry (1-based AppleScript indices).
public enum TabSwitchPlan {
    public enum Target: Equatable {
        /// Activate the existing tab at this 1-based index.
        case neighbor(index: Int)
        /// Open and activate a new empty tab.
        case newTab
    }

    /// Picks the switch target. The preferred neighbor is index+1, falling
    /// back to index-1 on the last tab. `neighborBlocked` is consulted at
    /// most once (the "one extra read" of the neighbor's URL): a blocked
    /// neighbor means a new tab — there is no second neighbor try. The only
    /// tab of a window and any degenerate geometry (count < 1, index outside
    /// the 1-based range) also mean a new tab, without probing.
    public static func target(
        activeIndex: Int, count: Int, neighborBlocked: (Int) -> Bool
    ) -> Target {
        guard count > 1, activeIndex >= 1, activeIndex <= count else { return .newTab }
        let neighbor = activeIndex < count ? activeIndex + 1 : activeIndex - 1
        return neighborBlocked(neighbor) ? .newTab : .neighbor(index: neighbor)
    }
}
