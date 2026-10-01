import AppKit
import TimerCore

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
// The menu is built before the delegate's launch callback runs, so the
// language has to be resolved here or every menu title would stay English.
L10n.refresh(preferences: Preferences())

let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
let appMenu = NSMenu()
let closeItem = NSMenuItem(
    title: tr("Popover schließen", "Close popover"),
    action: #selector(AppDelegate.closePopover(_:)),
    keyEquivalent: "q"
)
closeItem.target = delegate
appMenu.addItem(closeItem)
appMenuItem.submenu = appMenu
mainMenu.addItem(appMenuItem)

// An app without a Dock icon still needs an Edit menu: the standard shortcuts
// are *menu* commands, so without one ⌘C, ⌘V, ⌘X and ⌘A do nothing in every
// text field the app has — the minute input, the domain fields, everywhere
// (pasting a copied URL into a block list did nothing). Nil targets send each command
// down the responder chain, which is where the focused field picks it up.
let editMenuItem = NSMenuItem()
let editMenu = NSMenu(title: tr("Bearbeiten", "Edit"))
for (title, selector, key) in [
    (tr("Widerrufen", "Undo"), Selector(("undo:")), "z"),
    (tr("Wiederholen", "Redo"), Selector(("redo:")), "Z"),
] {
    editMenu.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key))
}
editMenu.addItem(.separator())
for (title, selector, key) in [
    (tr("Ausschneiden", "Cut"), #selector(NSText.cut(_:)), "x"),
    (tr("Kopieren", "Copy"), #selector(NSText.copy(_:)), "c"),
    (tr("Einsetzen", "Paste"), #selector(NSText.paste(_:)), "v"),
    (tr("Alles auswählen", "Select All"), #selector(NSText.selectAll(_:)), "a"),
] {
    editMenu.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key))
}
editMenuItem.submenu = editMenu
mainMenu.addItem(editMenuItem)

app.mainMenu = mainMenu

app.run()
