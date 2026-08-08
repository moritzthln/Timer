import AppKit

// Duplicate-instance guard: the LaunchAgent fallback and SMAppService could
// both fire at login; the younger instance yields immediately. Bare binaries
// (swift run) have no bundle identifier and skip the check.
if let bundleID = Bundle.main.bundleIdentifier {
    let ownPID = ProcessInfo.processInfo.processIdentifier
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.processIdentifier != ownPID }
    if !others.isEmpty {
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)

// Hidden main menu so ⌘Q works while the popover is key.
let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
let appMenu = NSMenu()
appMenu.addItem(
    NSMenuItem(
        title: "Quit Timer",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
    )
)
appMenuItem.submenu = appMenu
mainMenu.addItem(appMenuItem)
app.mainMenu = mainMenu

app.run()
