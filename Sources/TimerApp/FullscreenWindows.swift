import AppKit

/// The window server's view of an app's windows. It is the only source that
/// still answers once an app is **hidden**: a hidden app exposes no AX windows
/// at all, so a fullscreen window that survived a `hide()` would be invisible
/// to the block forever — which is exactly the state the user kept finding
/// (app gone from the screen, its fullscreen Space still sitting there with
/// the window in it).
///
/// Bounds and owner pid are permission-free. Window *titles* would need Screen
/// Recording and are never read.
enum FullscreenWindows {
    /// The window list is enumerated for the whole system, so a sweep over a
    /// dozen apps would ask for it a dozen times per second. One snapshot per
    /// tick is plenty — nothing decided here changes faster than that.
    private static let cacheLifetime = 0.15
    private static var cached: [[String: Any]] = []
    private static var cachedAt: Date?

    private static func windowList() -> [[String: Any]] {
        if let cachedAt, Date().timeIntervalSince(cachedAt) < cacheLifetime { return cached }
        cached = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []
        cachedAt = Date()
        return cached
    }

    /// Whether the app owns a window the size of a whole screen — the shape a
    /// native fullscreen window has, on whichever Space it lives.
    static func hasFullscreenWindow(pid: pid_t) -> Bool {
        let screens = NSScreen.screens.map(\.frame)
        guard !screens.isEmpty else { return false }
        return windowList().contains { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"]
            else { return false }
            // A maximised window stops below the menu bar, a fullscreen one
            // covers the display exactly — two points of slack for scaling.
            return screens.contains {
                abs($0.width - width) < 2 && abs($0.height - height) < 2
            }
        }
    }
}
