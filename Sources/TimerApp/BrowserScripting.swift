import AppKit

/// Shared AppleScript access to the supported browsers' active tab.
enum BrowserScripting {
    struct Browser {
        let bundleID: String
        let readURL: String
        let closeTab: String
    }

    static let supported: [Browser] = [
        Browser(
            bundleID: "com.apple.Safari",
            readURL: "tell application \"Safari\" to return URL of current tab of front window",
            closeTab: "tell application \"Safari\" to close current tab of front window"
        ),
        Browser(
            bundleID: "com.google.Chrome",
            readURL: "tell application \"Google Chrome\" to return URL of active tab of front window",
            closeTab: "tell application \"Google Chrome\" to close active tab of front window"
        ),
        Browser(
            bundleID: "company.thebrowser.Browser",
            readURL: "tell application \"Arc\" to return URL of active tab of front window",
            closeTab: "tell application \"Arc\" to close active tab of front window"
        ),
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
}
