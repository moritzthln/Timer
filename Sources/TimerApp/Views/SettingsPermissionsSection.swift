import SwiftUI
import AppKit
import TimerCore

/// v18 settings tab "Rechte": every permission and system hook the app needs,
/// in one place — the list to walk down after a reinstall, when macOS has
/// quietly reset half of them.
///
/// The cheap, non-prompting checks (Accessibility, login item, shortcuts
/// list) run when the settings window opens. The automation probes never do:
/// probing an unknown browser can surface the one-time macOS consent prompt,
/// so those only run on an explicit "Prüfen" / "Alle prüfen".
/// What the "Rechte" tab needs from the focus block: run the v21 fullscreen
/// diagnostic against the frontmost app and hand back one German status line.
/// Wired by StatusBarController — the ladder lives in FocusBlockController.
typealias FullscreenBlockTester = (@escaping (String) -> Void) -> Void

struct PermissionsSettingsSection: View {
    let preferences: Preferences
    @ObservedObject var focusMode: FocusModeController
    let onTestFullscreenBlock: FullscreenBlockTester?

    /// Traffic-light state of one row.
    private enum Level {
        case granted, unknown, missing

        var color: Color {
            switch self {
            case .granted: return .green
            case .unknown: return .orange
            case .missing: return .red
            }
        }
    }

    /// One row's rendered status: badge colour, short label, tooltip.
    private struct Status {
        let level: Level
        let label: String
        let help: String
    }

    @State private var accessibilityTrusted = false
    @State private var loginState: LaunchAtLogin.Status = .inactive
    /// Probe results per browser bundle id; missing = not probed yet.
    @State private var automation: [String: BrowserScripting.AutomationAccess] = [:]
    /// v21 diagnostic: seconds left to switch apps, then the reported line.
    @State private var testCountdown = 0
    @State private var testResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            accessibilityRow
            fullscreenTestRow
            ForEach(BrowserScripting.supported, id: \.bundleID) { browser in
                automationRow(browser)
            }
            shortcutsRow
            loginRow
            caption(tr("Nach einer Neuinstallation setzt macOS manche Rechte zurück — hier prüfen und neu erteilen.", "After a reinstall macOS resets some permissions — check them here and grant them again."))
                .padding(.top, 2)
        }
        .onAppear(perform: refreshQuietChecks)
    }

    private var header: some View {
        HStack {
            Text(tr("Rechte", "Permissions"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            Button(tr("Alle prüfen", "Check all"), action: checkAll)
                .controlSize(.small)
        }
    }

    // MARK: - Rows

    private var accessibilityRow: some View {
        row(title: tr("Bedienungshilfen (Vollbild-Block)", "Accessibility (fullscreen block)"), status: accessibilityStatus) {
            Button(tr("Öffnen", "Open")) { AccessibilityAccess.openSettings() }
                .controlSize(.small)
        }
    }

    /// v21: the fullscreen block is invisible until it fires, so this runs the
    /// real ladder on demand — hide, un-fullscreen, Space escape, cover — and
    /// prints what it took. The countdown is not decoration: clicking the
    /// button puts the Timer in front, so the user needs those seconds to
    /// switch to the app he wants to see blocked.
    private var fullscreenTestRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(tr("Vollbild-Block testen", "Test the fullscreen block"))
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(testCountdown > 0 ? tr("\(testCountdown) …", "\(testCountdown) …") : tr("Testen", "Test"), action: startTest)
                    .controlSize(.small)
                    .disabled(testCountdown > 0 || onTestFullscreenBlock == nil)
            }
            caption(testHint)
        }
    }

    private var testHint: String {
        if testCountdown > 0 {
            return tr("Jetzt in die App wechseln, die geprüft werden soll — gern im Vollbild.", "Switch to the app you want to test now — fullscreen is fine.")
        }
        if let testResult {
            return tr("Ergebnis: \(testResult). Eine versteckte App holt ein Klick im Dock zurück.", "Result: \(testResult). A hidden app comes back with a click in the Dock.")
        }
        return tr("Läuft einmal komplett gegen die App, die nach dem Klick vorne ist — ohne laufende Session.", "Runs once against whatever app is in front after the click — no session needed.")
    }

    private func automationRow(_ browser: BrowserScripting.Browser) -> some View {
        row(title: tr("Automation: \(browser.appName)", "Automation: \(browser.appName)"), status: automationStatus(browser)) {
            Button(tr("Prüfen", "Check")) { probe(browser) }
                .controlSize(.small)
            Button(tr("Öffnen", "Open"), action: openAutomationSettings)
                .controlSize(.small)
        }
    }

    private var shortcutsRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            row(title: tr("Kurzbefehle (Nicht stören)", "Shortcuts (Do Not Disturb)"), status: shortcutsStatus) {
                Button(tr("Prüfen", "Check")) { focusMode.refreshShortcutList() }
                    .controlSize(.small)
            }
            caption(tr("Anlegen und auswählen im Tab „Fokus“ → Nicht stören.", "Create and select them in the “Focus” tab → Do Not Disturb."))
        }
    }

    private var loginRow: some View {
        row(title: tr("Beim Anmelden starten", "Start at login"), status: loginStatus) {
            Button(tr("Öffnen", "Open")) { LaunchAtLogin.openLoginItemsSettings() }
                .controlSize(.small)
        }
    }

    /// Title line, then badge and actions — two lines per row keep the whole
    /// table readable at the settings window's fixed width.
    private func row(
        title: String, status: Status, @ViewBuilder actions: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                badge(status)
                Spacer(minLength: 0)
                actions()
            }
        }
    }

    private func badge(_ status: Status) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.level.color)
                .frame(width: 8, height: 8)
            Text(status.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .help(status.help)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Status

    private var accessibilityStatus: Status {
        accessibilityTrusted
            ? Status(
                level: .granted, label: tr("Erteilt", "Granted"),
                help: tr("Der Fokus-Block darf blockierte Apps aus dem Vollbild holen.", "The focus block may take blocked apps out of fullscreen.")
            )
            : Status(
                level: .missing, label: tr("Fehlt", "Missing"),
                help: tr("Ohne dieses Recht bleibt eine Vollbild-App sichtbar — der Block legt dann nur ein Hinweis-Overlay darüber.", "Without it a fullscreen app stays where it is — hiding alone is ignored there.")
            )
    }

    private func automationStatus(_ browser: BrowserScripting.Browser) -> Status {
        switch automation[browser.bundleID] {
        case .none:
            return Status(
                level: .unknown, label: tr("Nicht geprüft", "Not checked"),
                help: tr("Prüfen startet eine harmlose Abfrage — beim ersten Mal fragt macOS nach der Erlaubnis.", "Check runs a harmless query — the first time, macOS asks for permission.")
            )
        case .granted:
            return Status(
                level: .granted, label: tr("Erteilt", "Granted"),
                help: tr("Der Website-Block kann in \(browser.appName) den Tab wechseln.", "The website block can switch tabs in \(browser.appName).")
            )
        case .denied:
            return Status(
                level: .missing, label: tr("Fehlt", "Missing"),
                help: tr("macOS hat den Zugriff abgelehnt — unter Automation wieder erlauben.", "macOS denied access — allow it again under Automation.")
            )
        case .notRunning:
            return Status(
                level: .unknown, label: tr("Browser nicht geöffnet", "Browser not running"),
                help: tr("Nur ein laufender Browser lässt sich prüfen — \(browser.appName) starten und erneut prüfen.", "Only a running browser can be checked — start \(browser.appName) and check again.")
            )
        case .unknown(let code):
            return Status(
                level: .unknown, label: tr("Unklar (Fehler \(code))", "Unclear (error \(code))"),
                help: tr("Die Abfrage ist fehlgeschlagen, aber nicht wegen der Berechtigung.", "The query failed, but not because of the permission.")
            )
        }
    }

    /// Both configured shortcut names have to exist in `shortcuts list`.
    private var shortcutsStatus: Status {
        let wanted = [preferences.dndShortcutOn, preferences.dndShortcutOff]
        let help = tr("Gesucht: „\(wanted[0])“ und „\(wanted[1])“.", "Looking for “\(wanted[0])” and “\(wanted[1])”.")
        guard focusMode.shortcutsAvailable else {
            return Status(
                level: .unknown, label: tr("Kurzbefehle nicht verfügbar", "Shortcuts not available"),
                help: tr("Diesem macOS fehlt die Kurzbefehle-App.", "This macOS has no Shortcuts app.")
            )
        }
        let available = Set(focusMode.availableShortcuts)
        guard !available.isEmpty else {
            return Status(level: .unknown, label: tr("Nicht geprüft", "Not checked"), help: help)
        }
        let missing = wanted.filter { !available.contains($0) }
        guard missing.isEmpty else {
            return Status(
                level: .missing,
                label: tr("Fehlt: ", "Missing: ") + missing.joined(separator: ", "), help: help
            )
        }
        return Status(level: .granted, label: tr("Beide vorhanden", "Both present"), help: help)
    }

    private var loginStatus: Status {
        switch loginState {
        case .active:
            return Status(
                level: .granted, label: tr("Aktiv", "Active"), help: tr("Timer startet beim Anmelden.", "Timer starts at login.")
            )
        case .activeLaunchAgent:
            return Status(
                level: .granted, label: tr("Aktiv (LaunchAgent)", "Active (LaunchAgent)"),
                help: tr("Timer startet über einen eigenen LaunchAgent beim Anmelden.", "Timer starts at login through its own LaunchAgent.")
            )
        case .requiresApproval:
            return Status(
                level: .unknown, label: tr("Wartet auf Freigabe", "Waiting for approval"),
                help: tr("In den Systemeinstellungen unter Anmeldeobjekte freigeben.", "Approve it in System Settings under Login Items.")
            )
        case .inactive:
            return Status(
                level: .missing, label: tr("Aus", "Off"),
                help: tr("Timer startet nicht automatisch — im Tab „Allgemein“ einschalten.", "Timer does not start automatically — turn it on in the “General” tab.")
            )
        }
    }

    // MARK: - Checks

    /// Everything that can be read without asking macOS anything.
    private func refreshQuietChecks() {
        accessibilityTrusted = AccessibilityAccess.isTrusted
        loginState = LaunchAtLogin.status
        focusMode.refreshShortcutList()
    }

    private func checkAll() {
        refreshQuietChecks()
        for browser in BrowserScripting.supported {
            probe(browser)
        }
    }

    private func probe(_ browser: BrowserScripting.Browser) {
        automation[browser.bundleID] = BrowserScripting.probeAutomation(browser)
    }

    /// Three seconds to get out of the settings window, then the ladder runs
    /// against whatever ended up in front.
    private func startTest() {
        testResult = nil
        testCountdown = 3
        tickTest()
    }

    private func tickTest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            testCountdown -= 1
            guard testCountdown <= 0 else {
                tickTest()
                return
            }
            onTestFullscreenBlock?({ line in testResult = line })
        }
    }

    private func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
