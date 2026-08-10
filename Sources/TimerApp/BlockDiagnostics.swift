import AppKit
import ApplicationServices

/// Hidden `--block-diagnose` run: dumps what the Accessibility layer actually
/// answers for every running app into a text file, so a failing block can be
/// diagnosed with data instead of guesses. It has to live *inside* the app —
/// AX permissions are granted per binary, so a throwaway script would only
/// ever report its own missing permission.
///
/// Usage: quit the Timer, then
/// `open -a /Applications/Timer.app --args --block-diagnose`.
enum BlockDiagnostics {
    static let flag = "--block-diagnose"

    static var isRequested: Bool { CommandLine.arguments.contains(flag) }

    static func reportURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Timer/block-diagnose.txt")
    }

    /// Walks every regular app, reads its windows twice — once with the
    /// enforcer's 0.25 s messaging timeout, once with the system default — and
    /// tries the un-fullscreen write on each fullscreen window. Every step
    /// records its AX result code and how long it took.
    static func run() {
        var lines: [String] = []
        lines.append("AXIsProcessTrusted: \(AXIsProcessTrusted())")
        lines.append("frontmost: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "–")")
        lines.append("")

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular {
            let name = app.localizedName ?? app.bundleIdentifier ?? "?"
            lines.append("== \(name) [\(app.bundleIdentifier ?? "–")] pid \(app.processIdentifier)")
            lines.append("   hidden: \(app.isHidden)  active: \(app.isActive)")
            lines.append(contentsOf: probe(pid: app.processIdentifier, timeout: 0.25))
            lines.append(contentsOf: probe(pid: app.processIdentifier, timeout: nil))
            lines.append("")
        }

        let url = reportURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// One pass over an app's windows at the given messaging timeout.
    private static func probe(pid: pid_t, timeout: Float?) -> [String] {
        let label = timeout.map { "timeout \($0)s" } ?? "timeout default"
        let element = AXUIElementCreateApplication(pid)
        if let timeout { AXUIElementSetMessagingTimeout(element, timeout) }

        var value: CFTypeRef?
        let started = Date()
        let code = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
        let took = Int(Date().timeIntervalSince(started) * 1000)
        guard code == .success, let windows = value as? [AXUIElement] else {
            return ["   \(label): windows → \(code.rawValue) after \(took) ms"]
        }
        var lines = ["   \(label): \(windows.count) windows after \(took) ms"]
        for (index, window) in windows.enumerated() {
            var state: CFTypeRef?
            let readCode = AXUIElementCopyAttributeValue(
                window, "AXFullScreen" as CFString, &state
            )
            let fullscreen = (state as? Bool) ?? false
            guard readCode == .success else {
                lines.append("     #\(index) fullscreen? → \(readCode.rawValue)")
                continue
            }
            guard fullscreen else {
                lines.append("     #\(index) windowed")
                continue
            }
            let writeStarted = Date()
            let writeCode = AXUIElementSetAttributeValue(
                window, "AXFullScreen" as CFString, kCFBooleanFalse
            )
            let writeTook = Int(Date().timeIntervalSince(writeStarted) * 1000)
            lines.append(
                "     #\(index) FULLSCREEN → set false: \(writeCode.rawValue) after \(writeTook) ms"
            )
        }
        return lines
    }
}
