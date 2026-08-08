import AppKit
import ServiceManagement

enum LaunchAtLogin {
    enum Status: Equatable {
        case active // SMAppService enabled
        case requiresApproval // waiting for the user in System Settings
        case activeLaunchAgent // fallback plist installed
        case inactive
    }

    private static let agentLabel = "com.moritzthelen.timer"

    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .active
        case .requiresApproval:
            return .requiresApproval
        default:
            return FileManager.default.fileExists(atPath: agentURL.path)
                ? .activeLaunchAgent : .inactive
        }
    }

    static var isEnabled: Bool { status != .inactive }

    /// Enabling registers with SMAppService; a throw or a dead post-register
    /// status (notRegistered/notFound) falls back to a user LaunchAgent.
    /// requiresApproval is not dead — the settings UI deep-links to System
    /// Settings instead. Disabling removes whichever mechanism is active.
    static func setEnabled(_ enabled: Bool) throws {
        guard enabled else {
            try? SMAppService.mainApp.unregister()
            try removeLaunchAgentIfPresent()
            return
        }
        do {
            try SMAppService.mainApp.register()
        } catch {
            try installLaunchAgent()
            return
        }
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            break
        default:
            try installLaunchAgent()
        }
    }

    static func openLoginItemsSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - LaunchAgent fallback

    /// The installed bundle's executable; the spec's /Applications path when
    /// running outside a bundle (bare `swift run` binary).
    private static var launchAgentProgramPath: String {
        if let executable = Bundle.main.executableURL,
           executable.path.contains(".app/Contents/MacOS/") {
            return executable.path
        }
        return "/Applications/Timer.app/Contents/MacOS/TimerApp"
    }

    private static func installLaunchAgent() throws {
        let plist: [String: Any] = [
            "Label": agentLabel,
            "RunAtLoad": true,
            "ProgramArguments": [launchAgentProgramPath],
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
        try FileManager.default.createDirectory(
            at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: agentURL)
        runLaunchctl(["load", agentURL.path])
    }

    private static func removeLaunchAgentIfPresent() throws {
        guard FileManager.default.fileExists(atPath: agentURL.path) else { return }
        runLaunchctl(["unload", agentURL.path])
        try FileManager.default.removeItem(at: agentURL)
    }

    /// Synchronous best effort — launchctl load/unload returns immediately.
    private static func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Missing launchctl is not actionable here; the plist alone still
            // takes effect at next login.
        }
    }
}
