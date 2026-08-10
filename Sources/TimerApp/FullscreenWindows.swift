import AppKit

/// The window server's view of an app's windows. It is what the block falls
/// back to whenever Accessibility stays silent — and it does so often: an app
/// whose windows all live on another Space (every fullscreen app that is not
/// the active one) reports **zero** AX windows. Measured on this machine while
/// both sat in fullscreen:
///
///     Telegram: hidden=false → AX 0 windows | real window 1512x982
///     WhatsApp: hidden=false → AX 0 windows | real window 1512x949
///
/// Without this second opinion the block cannot even tell those two apart from
/// an app with nothing open, and blindly hiding them is what left their
/// fullscreen Spaces behind.
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

    /// Below this, a window is chrome rather than content: every app owns a
    /// 1512×33 menu-bar strip and a 64×64 stub in the list.
    private static let minContentWidth: CGFloat = 300
    private static let minContentHeight: CGFloat = 200
    /// A fullscreen window covers the display; a *maximised* one stops below
    /// the menu bar. Both count as "the screen is taken" — Catalyst apps
    /// report the second shape for real fullscreen (WhatsApp: 1512×949 on a
    /// 1512×982 screen). A normal large window (Chrome: 1512×884) stays out.
    private static let fullHeightSlack: CGFloat = 40

    /// Window numbers of everything currently on the active Space. A window
    /// the app owns that is *not* in here lives on another Space — which is
    /// where a second fullscreen window hides.
    private static func onScreenNumbers() -> Set<Int> {
        let listed = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []
        return Set(listed.compactMap { $0[kCGWindowNumber as String] as? Int })
    }

    /// Whether the app owns a real window that is not on the active Space.
    /// This is the evidence that one visit is not enough: an app can hold
    /// several fullscreen Spaces, and only the current one is ever reachable —
    /// Accessibility lists it, keyboard shortcuts hit it, the rest may as well
    /// not exist (user: "mehrere Chrome-Profile in zwei Vollbildern, nur eins
    /// wurde rausgeholt").
    static func hasWindowOnAnotherSpace(pid: pid_t) -> Bool {
        let onScreen = onScreenNumbers()
        return windowList().contains { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let number = window[kCGWindowNumber as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width >= minContentWidth, height >= minContentHeight
            else { return false }
            return !onScreen.contains(number)
        }
    }

    private static func windowList() -> [[String: Any]] {
        if let cachedAt, Date().timeIntervalSince(cachedAt) < cacheLifetime { return cached }
        cached = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []
        cachedAt = Date()
        return cached
    }

    /// Sizes of the app's real windows, largest first.
    private static func contentSizes(pid: pid_t) -> [CGSize] {
        windowList().compactMap { window -> CGSize? in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width >= minContentWidth, height >= minContentHeight
            else { return nil }
            return CGSize(width: width, height: height)
        }
    }

    /// Whether the app has any real window at all — the difference between
    /// "Accessibility cannot see it" and "there is nothing to see".
    static func hasContentWindow(pid: pid_t) -> Bool {
        !contentSizes(pid: pid).isEmpty
    }

    /// Whether one of those windows takes up a whole screen, on whichever
    /// Space it lives.
    static func hasFullscreenWindow(pid: pid_t) -> Bool {
        let screens = NSScreen.screens.map(\.frame)
        guard !screens.isEmpty else { return false }
        return contentSizes(pid: pid).contains { size in
            screens.contains { screen in
                abs(screen.width - size.width) < 2
                    && size.height >= screen.height - fullHeightSlack
            }
        }
    }
}
