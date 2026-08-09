import AppKit
import CoreGraphics

/// v22: where a browser's front window sits on screen — the geometry the site
/// cover is fitted into.
///
/// `CGWindowListCopyWindowInfo` hands out owner pid, layer and **bounds**
/// without any permission; only a window's *title* (`kCGWindowName`) requires
/// Screen Recording. This file never asks for a title, so v22 adds no
/// permission to the app — which is the whole reason the cover is placed from
/// window bounds instead of from the browser's own layout.
enum BrowserWindowBounds {
    /// The frontmost normal window of the given process, in AppKit screen
    /// coordinates, or nil when the process has none on screen.
    ///
    /// The list comes back ordered front to back, so the first match is the
    /// window the user is looking at. Layer 0 is the normal window level:
    /// it filters out the tooltip, popover and status windows a browser keeps
    /// around, which would otherwise be "in front" of the page.
    static func frontWindowFrame(pid: pid_t) -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]]
        else { return nil }
        for entry in entries {
            guard (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }
            return appKitFrame(fromDisplay: rect)
        }
        return nil
    }

    /// The frame of the screen showing most of the given (AppKit) frame — the
    /// clamp target for the cover. A window that overlaps nothing still gets
    /// the nearest answer; the content rect's clamp then rejects it.
    static func screenFrame(containing frame: CGRect) -> CGRect? {
        NSScreen.screens
            .max { overlap($0.frame, frame) < overlap($1.frame, frame) }?
            .frame
    }

    private static func overlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    /// The window server reports display coordinates: origin at the top-left
    /// of the primary display, y growing downwards. AppKit measures from that
    /// display's bottom-left upwards, and `NSScreen.screens.first` is exactly
    /// that display (its origin is AppKit's (0, 0)), so its `maxY` is the axis
    /// to mirror around.
    private static func appKitFrame(fromDisplay rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        return CGRect(
            x: rect.minX,
            y: primary.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
