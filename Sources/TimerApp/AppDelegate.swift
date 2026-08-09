import AppKit
import TimerCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let preferences = Preferences()
        let engine = TimerEngine(preferences: preferences)
        statusBarController = StatusBarController(engine: engine, preferences: preferences)
    }

    /// Target of the hidden ⌘Q menu item — see StatusBarController.closePopover().
    @objc func closePopover(_ sender: Any?) {
        statusBarController?.closePopover()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController?.prepareForTermination()
    }
}
