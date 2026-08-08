import AppKit

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
