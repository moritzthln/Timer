import AppKit

/// Shared AppleScript access to the supported browsers' front-window tabs.
enum BrowserScripting {
    struct Browser {
        /// Chromium-style dictionaries (Chrome; Arc claims compatibility and
        /// is probed at runtime) address the active tab by index; Safari
        /// addresses the "current tab" object.
        enum Style {
            case safari
            case chromium
        }

        let bundleID: String
        let appName: String
        let style: Style

        /// URL of the front window's active tab.
        var readURL: String {
            switch style {
            case .safari:
                return "tell application \"\(appName)\" to return URL of current tab of front window"
            case .chromium:
                return "tell application \"\(appName)\" to return URL of active tab of front window"
            }
        }

        /// v15 tab close; since v16 only the fallback for browsers whose
        /// tab-switch scripting fails at runtime.
        var closeTab: String {
            switch style {
            case .safari:
                return "tell application \"\(appName)\" to close current tab of front window"
            case .chromium:
                return "tell application \"\(appName)\" to close active tab of front window"
            }
        }

        /// Returns "index|count" for the front window (1-based active tab
        /// index and tab count) — the geometry behind `TabSwitchPlan`.
        var tabInfo: String {
            switch style {
            case .safari:
                return "tell application \"\(appName)\" to tell front window to"
                    + " return (index of current tab as text) & \"|\" & (count of tabs as text)"
            case .chromium:
                return "tell application \"\(appName)\" to tell front window to"
                    + " return (active tab index as text) & \"|\" & (count of tabs as text)"
            }
        }

        /// URL of an arbitrary tab — the "one extra read" probing whether
        /// the switch neighbor is blocked too.
        func tabURL(at index: Int) -> String {
            "tell application \"\(appName)\" to return URL of tab \(index) of front window"
        }

        /// Activates the tab at the 1-based index; the previously active
        /// (blocked) tab stays open in the background.
        func activateTab(at index: Int) -> String {
            switch style {
            case .safari:
                return "tell application \"\(appName)\" to tell front window to set current tab to tab \(index)"
            case .chromium:
                return "tell application \"\(appName)\" to set active tab index of front window to \(index)"
            }
        }

        /// Opens a new empty tab at the end and activates it.
        var newTab: String {
            switch style {
            case .safari:
                return """
                tell application "\(appName)"
                    tell front window
                        set current tab to (make new tab at end of tabs)
                    end tell
                end tell
                """
            case .chromium:
                return """
                tell application "\(appName)"
                    tell front window
                        make new tab
                        set active tab index to (count of tabs)
                    end tell
                end tell
                """
            }
        }
    }

    static let supported: [Browser] = [
        Browser(bundleID: "com.apple.Safari", appName: "Safari", style: .safari),
        Browser(bundleID: "com.google.Chrome", appName: "Google Chrome", style: .chromium),
        Browser(bundleID: "company.thebrowser.Browser", appName: "Arc", style: .chromium),
    ]

    static func browser(forBundleID bundleID: String?) -> Browser? {
        supported.first { $0.bundleID == bundleID }
    }

    /// Returns the script's string result, nil on any scripting/permission error.
    static func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result.stringValue
    }

    /// Runs a script for its side effect; true iff no scripting error —
    /// unlike `run`, usable for scripts without a string result.
    static func runVoid(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        return error == nil
    }

    /// Parses the "index|count" payload of a `tabInfo` read.
    static func parseTabInfo(_ payload: String?) -> (index: Int, count: Int)? {
        let parts = (payload ?? "").split(separator: "|")
        guard parts.count == 2, let index = Int(parts[0]), let count = Int(parts[1]) else {
            return nil
        }
        return (index: index, count: count)
    }
}
