import AppKit
import TimerCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let preferences = Preferences()
        let engine = TimerEngine(preferences: preferences)
        statusBarController = StatusBarController(engine: engine, preferences: preferences)
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController?.flushActivity()
    }
}
