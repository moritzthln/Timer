import Foundation
import Combine
import TimerCore

/// Couples focus sessions to the macOS Focus mode via two user-selected
/// Shortcuts (v8: names come from preferences, defaults match the v7 fixed
/// names), run through /usr/bin/shortcuts. Same activity semantics as the
/// focus block (`FocusBlockRules.isActive`), gated by the DND toggle.
final class FocusModeController: ObservableObject {
    private static let binaryPath = "/usr/bin/shortcuts"

    /// One-line status for the settings section; replaced, never accumulated.
    /// nil after a successful run.
    @Published private(set) var statusMessage: String?

    /// `shortcuts list` output for the settings dropdowns, alphabetical.
    @Published private(set) var availableShortcuts: [String] = []

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
        run(shortcut: active ? preferences.dndShortcutOn : preferences.dndShortcutOff)
    }

    /// Settings "Testen" buttons — run the currently selected shortcuts.
    func test(on: Bool) {
        run(shortcut: on ? preferences.dndShortcutOn : preferences.dndShortcutOff)
    }

    /// Best-effort off-shortcut on app quit. Spawns without waiting — the
    /// child process survives our exit.
    func deactivateForTermination() {
        guard active, shortcutsAvailable else { return }
        active = false
        _ = try? Self.makeProcess(arguments: ["run", preferences.dndShortcutOff]).run()
    }

    /// Repopulates `availableShortcuts` from `shortcuts list`. The pipe is
    /// drained on a background queue (no 64 KB pipe-buffer deadlock), the
    /// published list updates on main.
    func refreshShortcutList() {
        guard shortcutsAvailable else { return }
        let process = Self.makeProcess(arguments: ["list"])
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            return // dropdown keeps its previous content
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let names = (String(data: data, encoding: .utf8) ?? "")
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            DispatchQueue.main.async {
                self?.availableShortcuts = names
            }
        }
    }

    // MARK: - Process plumbing

    private static func makeProcess(arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
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
        let process = Self.makeProcess(arguments: ["run", shortcut])
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
