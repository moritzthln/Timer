import Foundation
import Combine
import TimerCore

/// Couples focus sessions to the macOS Focus mode via two user-created
/// Shortcuts, run through /usr/bin/shortcuts. Same activity semantics as the
/// focus block (`FocusBlockRules.isActive`), gated by the DND toggle.
final class FocusModeController: ObservableObject {
    static let onShortcutName = "Timer Fokus an"
    static let offShortcutName = "Timer Fokus aus"
    private static let binaryPath = "/usr/bin/shortcuts"

    /// One-line status for the settings section; replaced, never accumulated.
    /// nil after a successful run.
    @Published private(set) var statusMessage: String?

    /// False on ancient macOS without the Shortcuts CLI (defensive — the
    /// deployment target is macOS 13, where it always exists).
    let shortcutsAvailable = FileManager.default.isExecutableFile(atPath: FocusModeController.binaryPath)

    private let preferences: Preferences
    private var active = false

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Reevaluates against the engine phase; idempotent. On inactive→active
    /// runs the on-shortcut, on active→inactive the off-shortcut.
    func update(phase: TimerEngine.Phase) {
        let shouldBeActive = FocusBlockRules.isActive(phase: phase, enabled: preferences.dndEnabled)
        guard shouldBeActive != active else { return }
        active = shouldBeActive
        run(shortcut: active ? Self.onShortcutName : Self.offShortcutName)
    }

    /// Settings "Testen" buttons.
    func test(on: Bool) {
        run(shortcut: on ? Self.onShortcutName : Self.offShortcutName)
    }

    /// Best-effort off-shortcut on app quit. Spawns without waiting — the
    /// child process survives our exit.
    func deactivateForTermination() {
        guard active, shortcutsAvailable else { return }
        active = false
        _ = try? Self.makeProcess(shortcut: Self.offShortcutName).run()
    }

    // MARK: - Process plumbing

    private static func makeProcess(shortcut: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["run", shortcut]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }

    /// Runs the shortcut asynchronously; `Process.run()` only spawns, the
    /// exit status arrives via the termination handler — the main thread is
    /// never blocked.
    private func run(shortcut: String) {
        guard shortcutsAvailable else {
            statusMessage = "Benötigt macOS 12+ (Kurzbefehle)."
            return
        }
        let process = Self.makeProcess(shortcut: shortcut)
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                if finished.terminationStatus == 0 {
                    self?.statusMessage = nil
                } else {
                    self?.statusMessage = "Kurzbefehl '\(shortcut)' nicht gefunden — Anleitung oben."
                }
            }
        }
        do {
            try process.run()
        } catch {
            statusMessage = "Kurzbefehl '\(shortcut)' konnte nicht gestartet werden."
        }
    }
}
