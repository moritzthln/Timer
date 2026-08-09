import CoreGraphics

/// v22: where the site cover may be drawn inside a browser window. Covering
/// the whole window would be a trap — escaping a blocked tab needs the tab
/// bar — so the cover gets the content area only: the window frame minus the
/// browser's chrome.
///
/// The insets are **approximations** of each browser's default chrome, and
/// deliberately generous: if a browser's real chrome is taller than the value
/// here, the cover simply starts a few points lower (a sliver of page shows
/// through), never higher (the tab bar would become unclickable). Nothing here
/// reads the browser's actual layout — that would need Accessibility or Screen
/// Recording, and v22 needs neither.
public enum BrowserChromeInsets {
    /// Chrome that sits above (`top`) and beside (`left`) the page.
    public struct Insets: Equatable {
        public let top: CGFloat
        public let left: CGFloat

        public init(top: CGFloat, left: CGFloat) {
            self.top = top
            self.left = left
        }
    }

    /// Below this a cover would be an unreadable smudge — mini windows and
    /// picture-in-picture-sized browsers skip straight to the tab switch.
    public static let minimumContentSize = CGSize(width: 200, height: 150)

    /// Safari: title bar + unified tab/address bar. Chrome: tab strip plus a
    /// separate omnibox row. Arc: the same Chromium chrome height, but its tab
    /// strip is a sidebar on the left — 280 pt of it, and it must stay
    /// clickable or the cover cannot be escaped at all. Anything unknown gets
    /// the tallest top inset (starting lower is the safe error).
    public static func insets(forBundleID bundleID: String) -> Insets {
        switch bundleID {
        case "com.apple.Safari": return Insets(top: 78, left: 0)
        case "com.google.Chrome": return Insets(top: 92, left: 0)
        case "company.thebrowser.Browser": return Insets(top: 92, left: 280)
        default: return Insets(top: 92, left: 0)
        }
    }

    /// The frame the cover should occupy, or nil when there is no room for
    /// one. Every rect here is in AppKit screen coordinates (origin
    /// bottom-left, y growing upwards), so the top chrome is taken off the
    /// height and the origin stays put; the caller flips the window server's
    /// top-left bounds once, before calling in.
    ///
    /// Order matters: insets first, then the clamp to the screen (a window
    /// half outside it must not be covered outside it), then the minimum-size
    /// guard on what is actually left.
    public static func contentRect(
        windowFrame: CGRect, bundleID: String, screenFrame: CGRect? = nil
    ) -> CGRect? {
        let insets = insets(forBundleID: bundleID)
        var rect = CGRect(
            x: windowFrame.minX + insets.left,
            y: windowFrame.minY,
            width: windowFrame.width - insets.left,
            height: windowFrame.height - insets.top
        )
        guard rect.width > 0, rect.height > 0 else { return nil }
        if let screenFrame {
            rect = rect.intersection(screenFrame)
            guard !rect.isNull else { return nil }
        }
        guard rect.width >= minimumContentSize.width,
              rect.height >= minimumContentSize.height
        else { return nil }
        return rect
    }
}
