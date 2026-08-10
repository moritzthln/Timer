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

    /// `--block-watch` samples one app for half a minute instead of dumping
    /// everything once — the only way to catch a state the user has to create
    /// by hand (put Chrome in fullscreen while it records).
    static let watchFlag = "--block-watch"
    static var isWatching: Bool { CommandLine.arguments.contains(watchFlag) }

    static func reportURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Timer/block-diagnose.txt")
    }

    /// Samples one app once a second for 30 s: what Accessibility says about
    /// its windows, what the window server sees, and — crucially — whether the
    /// fullscreen attribute is even settable. Written after every sample, so
    /// the file is readable while it runs.
    static func watch(bundleID: String) {
        var lines = ["watching \(bundleID), 30 samples", ""]
        var sample = 0
        func step() {
            sample += 1
            let apps = NSWorkspace.shared.runningApplications.filter {
                $0.bundleIdentifier == bundleID
            }
            // From here on the sample also *tries* the exit, so the log shows
            // whether the write works per window — not just what it reads.
            let acting = sample > 15
            if apps.isEmpty { lines.append("[\(sample)] not running") }
            for app in apps {
                lines.append(
                    "[\(sample)] pid \(app.processIdentifier) hidden=\(app.isHidden)"
                    + " active=\(app.isActive)\(acting ? " ACTING" : "")"
                )
                lines.append(contentsOf: axDetail(pid: app.processIdentifier, acting: acting))
                lines.append(contentsOf: cgDetail(pid: app.processIdentifier))
            }
            write(lines)
            if sample < 30 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { step() }
            }
        }
        step()
    }

    /// Per window: is it fullscreen, and may we even write that attribute?
    private static func axDetail(pid: pid_t, acting: Bool = false) -> [String] {
        let element = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let code = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
        guard code == .success, let windows = value as? [AXUIElement] else {
            return ["    AX: windows → \(code.rawValue)"]
        }
        return ["    AX: \(windows.count) windows"] + windows.enumerated().map { index, window in
            var state: CFTypeRef?
            let read = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &state)
            var settable: DarwinBoolean = false
            AXUIElementIsAttributeSettable(window, "AXFullScreen" as CFString, &settable)
            var size: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size)
            var box = CGSize.zero
            if let size { AXValueGetValue(size as! AXValue, .cgSize, &box) }
            let isFull = (state as? Bool) ?? false
            let full = (state as? Bool).map(String.init) ?? "read \(read.rawValue)"
            var line = "      #\(index) fullscreen=\(full) settable=\(settable.boolValue)"
                + " size=\(Int(box.width))x\(Int(box.height))"
            if acting, isFull {
                let result = AXUIElementSetAttributeValue(
                    window, "AXFullScreen" as CFString, kCFBooleanFalse
                )
                line += " → set false: \(result.rawValue)"
            }
            return line
        }
    }

    private static func cgDetail(pid: pid_t) -> [String] {
        let listed = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []
        let sizes = listed.compactMap { window -> String? in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width >= 300, height >= 200 else { return nil }
            return "\(Int(width))x\(Int(height))@\(Int(bounds["X"] ?? 0)),\(Int(bounds["Y"] ?? 0))"
        }
        return ["    CG: " + sizes.joined(separator: " ")]
    }

    private static func write(_ lines: [String]) {
        let url = reportURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
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

        write(lines)
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
