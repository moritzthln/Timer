import AppKit
import TimerCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let preferences = Preferences()
        // Before anything is rendered: every view resolves its strings once,
        // at build time.
        L10n.refresh(preferences: preferences)
        let engine = TimerEngine(preferences: preferences)
        statusBarController = StatusBarController(engine: engine, preferences: preferences)
        if BlockDiagnostics.isWatching {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                BlockDiagnostics.watch(bundleID: "com.google.Chrome")
            }
        } else if BlockDiagnostics.isRequested {
            // A moment for the workspace list to settle before it is dumped.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { BlockDiagnostics.run() }
        }
    }

    /// Target of the hidden ⌘Q menu item — see StatusBarController.closePopover().
    @objc func closePopover(_ sender: Any?) {
        statusBarController?.closePopover()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController?.prepareForTermination()
    }
}
