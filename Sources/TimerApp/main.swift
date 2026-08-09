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

// Hidden main menu. ⌘Q closes the popover rather than quitting: a reflexive
// ⌘Q in the popover used to kill the running session, the activity tracking
// and the block at once. Quitting lives in the ⋯ menu and the status item's
// right-click menu, both without a shortcut.
let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
let appMenu = NSMenu()
let closeItem = NSMenuItem(
    title: "Popover schließen",
    action: #selector(AppDelegate.closePopover(_:)),
    keyEquivalent: "q"
)
closeItem.target = delegate
appMenu.addItem(closeItem)
appMenuItem.submenu = appMenu
mainMenu.addItem(appMenuItem)
app.mainMenu = mainMenu

app.run()
