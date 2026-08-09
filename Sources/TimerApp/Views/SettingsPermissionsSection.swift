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
struct PermissionsSettingsSection: View {
    let preferences: Preferences
    @ObservedObject var focusMode: FocusModeController

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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            accessibilityRow
            ForEach(BrowserScripting.supported, id: \.bundleID) { browser in
                automationRow(browser)
            }
            shortcutsRow
            loginRow
            caption("Nach einer Neuinstallation setzt macOS manche Rechte zurück — hier prüfen und neu erteilen.")
                .padding(.top, 2)
        }
        .onAppear(perform: refreshQuietChecks)
    }

    private var header: some View {
        HStack {
            Text("Rechte")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            Button("Alle prüfen", action: checkAll)
                .controlSize(.small)
        }
    }

    // MARK: - Rows

    private var accessibilityRow: some View {
        row(title: "Bedienungshilfen (Vollbild-Block)", status: accessibilityStatus) {
            Button("Öffnen") { AccessibilityAccess.openSettings() }
                .controlSize(.small)
        }
    }

    private func automationRow(_ browser: BrowserScripting.Browser) -> some View {
        row(title: "Automation: \(browser.appName)", status: automationStatus(browser)) {
            Button("Prüfen") { probe(browser) }
                .controlSize(.small)
            Button("Öffnen", action: openAutomationSettings)
                .controlSize(.small)
        }
    }

    private var shortcutsRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            row(title: "Kurzbefehle (Nicht stören)", status: shortcutsStatus) {
                Button("Prüfen") { focusMode.refreshShortcutList() }
                    .controlSize(.small)
            }
            caption("Anlegen und auswählen im Tab „Fokus“ → Nicht stören.")
        }
    }

    private var loginRow: some View {
        row(title: "Beim Anmelden starten", status: loginStatus) {
            Button("Öffnen") { LaunchAtLogin.openLoginItemsSettings() }
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
                level: .granted, label: "Erteilt",
                help: "Der Fokus-Block darf blockierte Apps aus dem Vollbild holen."
            )
            : Status(
                level: .missing, label: "Fehlt",
                help: "Ohne dieses Recht bleibt eine Vollbild-App sichtbar — der Block legt dann nur ein Hinweis-Overlay darüber."
            )
    }

    private func automationStatus(_ browser: BrowserScripting.Browser) -> Status {
        switch automation[browser.bundleID] {
        case .none:
            return Status(
                level: .unknown, label: "Nicht geprüft",
                help: "Prüfen startet eine harmlose Abfrage — beim ersten Mal fragt macOS nach der Erlaubnis."
            )
        case .granted:
            return Status(
                level: .granted, label: "Erteilt",
                help: "Der Website-Block kann in \(browser.appName) den Tab wechseln."
            )
        case .denied:
            return Status(
                level: .missing, label: "Fehlt",
                help: "macOS hat den Zugriff abgelehnt — unter Automation wieder erlauben."
            )
        case .notRunning:
            return Status(
                level: .unknown, label: "Browser nicht geöffnet",
                help: "Nur ein laufender Browser lässt sich prüfen — \(browser.appName) starten und erneut prüfen."
            )
        case .unknown(let code):
            return Status(
                level: .unknown, label: "Unklar (Fehler \(code))",
                help: "Die Abfrage ist fehlgeschlagen, aber nicht wegen der Berechtigung."
            )
        }
    }

    /// Both configured shortcut names have to exist in `shortcuts list`.
    private var shortcutsStatus: Status {
        let wanted = [preferences.dndShortcutOn, preferences.dndShortcutOff]
        let help = "Gesucht: „\(wanted[0])“ und „\(wanted[1])“."
        guard focusMode.shortcutsAvailable else {
            return Status(
                level: .unknown, label: "Kurzbefehle nicht verfügbar",
                help: "Diesem macOS fehlt die Kurzbefehle-App."
            )
        }
        let available = Set(focusMode.availableShortcuts)
        guard !available.isEmpty else {
            return Status(level: .unknown, label: "Nicht geprüft", help: help)
        }
        let missing = wanted.filter { !available.contains($0) }
        guard missing.isEmpty else {
            return Status(
                level: .missing, label: "Fehlt: \(missing.joined(separator: ", "))", help: help
            )
        }
        return Status(level: .granted, label: "Beide vorhanden", help: help)
    }

    private var loginStatus: Status {
        switch loginState {
        case .active:
            return Status(
                level: .granted, label: "Aktiv", help: "Timer startet beim Anmelden."
            )
        case .activeLaunchAgent:
            return Status(
                level: .granted, label: "Aktiv (LaunchAgent)",
                help: "Timer startet über einen eigenen LaunchAgent beim Anmelden."
            )
        case .requiresApproval:
            return Status(
                level: .unknown, label: "Wartet auf Freigabe",
                help: "In den Systemeinstellungen unter Anmeldeobjekte freigeben."
            )
        case .inactive:
            return Status(
                level: .missing, label: "Aus",
                help: "Timer startet nicht automatisch — im Tab „Allgemein“ einschalten."
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

    private func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
