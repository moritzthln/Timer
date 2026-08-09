import CoreGraphics
import Foundation
import TimerCore

func runBrowserChromeInsetsTests() {
    let safari = "com.apple.Safari"
    let chrome = "com.google.Chrome"
    let arc = "company.thebrowser.Browser"
    // AppKit screen coordinates (origin bottom-left), as everywhere below.
    let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)

    test("Safari loses 78 pt at the top and nothing at the side") {
        let rect = BrowserChromeInsets.contentRect(
            windowFrame: CGRect(x: 100, y: 50, width: 1_000, height: 800), bundleID: safari
        )
        try expectEqual(rect, CGRect(x: 100, y: 50, width: 1_000, height: 722), "Safari inset")
    }

    test("Chrome loses 92 pt at the top") {
        let rect = BrowserChromeInsets.contentRect(
            windowFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800), bundleID: chrome
        )
        try expectEqual(rect, CGRect(x: 0, y: 0, width: 1_000, height: 708), "Chrome inset")
    }

    test("Arc also keeps its 280 pt tab sidebar clickable") {
        let rect = BrowserChromeInsets.contentRect(
            windowFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800), bundleID: arc
        )
        try expectEqual(rect, CGRect(x: 280, y: 0, width: 720, height: 708), "Arc insets")
    }

    test("an unknown browser gets the tallest chrome") {
        let rect = BrowserChromeInsets.contentRect(
            windowFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800), bundleID: "org.mozilla.firefox"
        )
        try expectEqual(
            rect, CGRect(x: 0, y: 0, width: 1_000, height: 708),
            "unknown chrome starts lower rather than higher"
        )
    }

    test("a window too short for a readable cover is skipped") {
        try expectNil(
            BrowserChromeInsets.contentRect(
                windowFrame: CGRect(x: 0, y: 0, width: 800, height: 200), bundleID: safari
            ),
            "122 pt of content is below the 150 pt minimum"
        )
    }

    test("a window too narrow for a readable cover is skipped") {
        try expectNil(
            BrowserChromeInsets.contentRect(
                windowFrame: CGRect(x: 0, y: 0, width: 460, height: 800), bundleID: arc
            ),
            "180 pt of content is below the 200 pt minimum"
        )
    }

    test("chrome taller than the window never yields a negative rect") {
        try expectNil(
            BrowserChromeInsets.contentRect(
                windowFrame: CGRect(x: 0, y: 0, width: 800, height: 40), bundleID: chrome
            ),
            "a window shorter than its own chrome has no content area"
        )
    }

    test("a window hanging off the screen is clamped to it") {
        let rect = BrowserChromeInsets.contentRect(
            windowFrame: CGRect(x: 1_000, y: 0, width: 1_000, height: 800),
            bundleID: safari, screenFrame: screen
        )
        try expectEqual(
            rect, CGRect(x: 1_000, y: 0, width: 440, height: 722),
            "the cover never reaches past the screen"
        )
    }

    test("a window on another screen clamps away to nothing") {
        try expectNil(
            BrowserChromeInsets.contentRect(
                windowFrame: CGRect(x: 2_000, y: 0, width: 1_000, height: 800),
                bundleID: safari, screenFrame: screen
            ),
            "no overlap with the passed screen means no cover"
        )
    }

    test("clamping below the minimum size skips the cover too") {
        try expectNil(
            BrowserChromeInsets.contentRect(
                windowFrame: CGRect(x: 1_300, y: 0, width: 1_000, height: 800),
                bundleID: safari, screenFrame: screen
            ),
            "140 pt of visible content is below the 200 pt minimum"
        )
    }

    test("a degenerate window frame yields no cover") {
        try expectNil(
            BrowserChromeInsets.contentRect(windowFrame: .zero, bundleID: chrome),
            "zero size has nothing to cover"
        )
    }
}
