import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TimerCore

/// The settings "Fokus-Block" section, extracted in v15 to keep SettingsView
/// under the size limit. Two subsections mirror the two block modes: the
/// blocklist ("Blockieren", unchanged v4 UI) and the allowlist
/// ("Nur Erlaubte", same UI pattern incl. NSMenu picker + live write-through).
/// v24 adds a third one for the emergency mode, which runs on allowlist
/// semantics but independently of the shield and of any timer.
struct FocusBlockSettingsSection: View {
    let preferences: Preferences

    @State private var blockedApps: [BlockedApp] = []
    @State private var blockedDomains: [String] = []
    @State private var newBlockedDomain = ""
    @State private var allowedApps: [BlockedApp] = []
    @State private var allowedDomains: [String] = []
    @State private var newAllowedDomain = ""
    @State private var emergencyApps: [BlockedApp] = []
    @State private var emergencyDomains: [String] = []
    @State private var newEmergencyDomain = ""
    @State private var emergencyMinutesText = ""
    @State private var shieldEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            subsectionTitle("Blockieren")
            VStack(alignment: .leading, spacing: 4) {
                blockedAppList
                blockedDomainList
            }
            subsectionTitle("Nur Erlaubte")
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                allowedAppList
                allowedDomainList
                caption("Leere Liste = dieser Teil blockt nichts.")
            }
            emergencySubsection
            captions
        }
        .onAppear(perform: load)
    }

    // MARK: - Header and captions

    /// Header row doubles as live state display, so the settings window
    /// itself reveals whether the shield would block right now.
    private var header: some View {
        HStack {
            Text("Fokus-Block")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            Text(shieldEnabled ? "Schild: an" : "Schild: aus")
                .font(.caption)
                .foregroundStyle(shieldEnabled ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
        }
    }

    private func subsectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var captions: some View {
        VStack(alignment: .leading, spacing: 2) {
            caption("Aktiv während Fokus-Sessions, wenn das Schild im Popover an ist.")
            caption("Website-Block braucht die Automation-Berechtigung (macOS fragt beim ersten Mal).")
            // v18: the permission status itself lives in the "Rechte" tab —
            // one place for all of them, so this stays a pointer.
            caption("Vollbild-Apps brauchen zusätzlich die Bedienungshilfen — Status im Tab „Rechte“.")
        }
        .padding(.top, 2)
    }

    // MARK: - Blocklist subsection

    private var blockedAppList: some View {
        Group {
            appRows(blockedApps) { bundleID in
                blockedApps.removeAll { $0.bundleID == bundleID }
                preferences.blockedApps = blockedApps
            }
            // v7: plain bordered button + programmatic NSMenu; the previous
            // SwiftUI Menu with .menuStyle(.borderlessButton) never opened.
            Button("App hinzufügen") {
                showAppPicker(
                    excluded: Self.unblockableBundleIDs(), listed: blockedApps,
                    add: addBlockedApp
                )
            }
            .controlSize(.small)
        }
    }

    private var blockedDomainList: some View {
        Group {
            domainRows(blockedDomains) { domain in
                blockedDomains.removeAll { $0 == domain }
                preferences.blockedDomains = blockedDomains
            }
            domainAddField($newBlockedDomain, placeholder: "instagram.com", commit: commitBlockedDomain)
        }
    }

    /// Commits through Preferences (dedupe + arm-on-first-entry live there)
    /// and re-reads the stored state so the list shows what actually stuck.
    private func addBlockedApp(_ app: BlockedApp) {
        preferences.addBlockedApp(app)
        blockedApps = preferences.blockedApps
        shieldEnabled = preferences.focusBlockEnabled
    }

    /// Single commit path for Enter and the button: Preferences sanitizes,
    /// dedupes, and stores; the list re-reads what actually persisted
    /// (write-through verification) and the field only clears on success.
    private func commitBlockedDomain() {
        let stored = preferences.addBlockedDomain(newBlockedDomain)
        blockedDomains = preferences.blockedDomains
        shieldEnabled = preferences.focusBlockEnabled
        if stored != nil { newBlockedDomain = "" }
    }

    // MARK: - Allowlist subsection (v15)

    private var allowedAppList: some View {
        Group {
            appRows(allowedApps) { bundleID in
                allowedApps.removeAll { $0.bundleID == bundleID }
                preferences.allowedApps = allowedApps
            }
            Button("App hinzufügen") {
                showAppPicker(
                    excluded: Self.implicitlyAllowedBundleIDs(), listed: allowedApps,
                    add: addAllowedApp
                )
            }
            .controlSize(.small)
        }
    }

    private var allowedDomainList: some View {
        Group {
            domainRows(allowedDomains) { domain in
                allowedDomains.removeAll { $0 == domain }
                preferences.allowedDomains = allowedDomains
            }
            domainAddField($newAllowedDomain, placeholder: "wikipedia.org", commit: commitAllowedDomain)
        }
    }

    /// First allowlist entry arms the shield and switches the mode
    /// (arm-on-configure lives in Preferences); re-read what stuck.
    private func addAllowedApp(_ app: BlockedApp) {
        preferences.addAllowedApp(app)
        allowedApps = preferences.allowedApps
        shieldEnabled = preferences.focusBlockEnabled
    }

    private func commitAllowedDomain() {
        let stored = preferences.addAllowedDomain(newAllowedDomain)
        allowedDomains = preferences.allowedDomains
        shieldEnabled = preferences.focusBlockEnabled
        if stored != nil { newAllowedDomain = "" }
    }

    // MARK: - Emergency subsection (v24)

    /// Same UI pattern as the two above; the only extra is the default
    /// duration, which the popover's start panel offers.
    /// v24.1: while a session runs the lists are frozen. Otherwise emptying
    /// the list mid-session would lift the block without ever holding the
    /// cancel button — the ten-second hold is meant to be the only way out.
    private var emergencyRunning: Bool {
        preferences.emergencySession() != nil
    }

    private var emergencySubsection: some View {
        VStack(alignment: .leading, spacing: 4) {
            subsectionTitle("Notfall-Modus")
                .padding(.top, 6)
            if emergencyRunning {
                caption("Notfall-Modus läuft — Listen sind bis zum Ende gesperrt.")
                    .foregroundStyle(Color.orange)
            }
            appRows(emergencyApps) { bundleID in
                emergencyApps.removeAll { $0.bundleID == bundleID }
                preferences.emergencyApps = emergencyApps
            }
            Button("App hinzufügen") {
                showAppPicker(
                    excluded: Self.implicitlyAllowedBundleIDs(), listed: emergencyApps,
                    add: addEmergencyApp
                )
            }
            .controlSize(.small)
            domainRows(emergencyDomains) { domain in
                emergencyDomains.removeAll { $0 == domain }
                preferences.emergencyDomains = emergencyDomains
            }
            domainAddField(
                $newEmergencyDomain, placeholder: "wikipedia.org", commit: commitEmergencyDomain
            )
            emergencyDurationRow
            caption("Läuft unabhängig vom Schild und von jedem Timer — Start im Popover unter „⋯“ oder per Hotkey.")
            caption("Leere App-Liste = alles außer Timer, Finder und Systemeinstellungen wird ausgeblendet. Leere Website-Liste = keine Seite wird gesperrt.")
        }
        .disabled(emergencyRunning)
    }

    private var emergencyDurationRow: some View {
        HStack {
            Text("Standard-Dauer (min)")
                .font(.system(size: 12))
            TextField("", text: Binding(
                get: { emergencyMinutesText },
                set: storeEmergencyMinutes
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: 46)
            .onSubmit { emergencyMinutesText = String(preferences.emergencyMinutes) }
            Text("max. \(EmergencyMode.maximumMinutes)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// v9 live-save with write-through: an in-range value is stored on every
    /// keystroke and re-read, anything else stays pending until Enter snaps
    /// the field back to what is actually stored.
    private func storeEmergencyMinutes(_ raw: String) {
        emergencyMinutesText = String(raw.filter(\.isNumber).prefix(2))
        guard let value = Int(emergencyMinutesText),
              (EmergencyMode.minimumMinutes...EmergencyMode.maximumMinutes).contains(value)
        else { return }
        preferences.emergencyMinutes = value
        emergencyMinutesText = String(preferences.emergencyMinutes)
    }

    private func addEmergencyApp(_ app: BlockedApp) {
        preferences.addEmergencyApp(app)
        emergencyApps = preferences.emergencyApps
    }

    private func commitEmergencyDomain() {
        let stored = preferences.addEmergencyDomain(newEmergencyDomain)
        emergencyDomains = preferences.emergencyDomains
        if stored != nil { newEmergencyDomain = "" }
    }

    // MARK: - Shared rows

    private func appRows(
        _ apps: [BlockedApp], remove: @escaping (String) -> Void
    ) -> some View {
        ForEach(apps, id: \.bundleID) { app in
            HStack {
                Text(app.name).font(.system(size: 12))
                Spacer()
                Button {
                    remove(app.bundleID)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func domainRows(
        _ domains: [String], remove: @escaping (String) -> Void
    ) -> some View {
        ForEach(domains, id: \.self) { domain in
            HStack {
                Text(domain).font(.system(size: 12, design: .monospaced))
                Spacer()
                Button {
                    remove(domain)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func domainAddField(
        _ text: Binding<String>, placeholder: String, commit: @escaping () -> Void
    ) -> some View {
        HStack {
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .onSubmit(commit)
            Button("Hinzufügen", action: commit)
                .controlSize(.small)
        }
    }

    // MARK: - App picker

    /// NSMenuItem holds its target weakly; `showAppPicker` keeps an instance
    /// alive for the synchronous popup so selections reach the closures.
    private final class AppPickerTarget: NSObject {
        let onPick: (BlockedApp) -> Void
        let onOther: () -> Void

        init(onPick: @escaping (BlockedApp) -> Void, onOther: @escaping () -> Void) {
            self.onPick = onPick
            self.onOther = onOther
        }

        @objc func pick(_ sender: NSMenuItem) {
            guard let candidate = sender.representedObject as? BlockedApp else { return }
            onPick(candidate)
        }

        @objc func other() { onOther() }
    }

    /// Pops a programmatic NSMenu at the mouse (i.e. at the clicked button).
    private func showAppPicker(
        excluded: Set<String>, listed: [BlockedApp], add: @escaping (BlockedApp) -> Void
    ) {
        let menu = NSMenu()
        let target = AppPickerTarget(
            onPick: { add($0) },
            onOther: { pickAppFromDisk(excluded: excluded, add: add) }
        )
        for candidate in runningUserApps(excluded: excluded, listed: listed) {
            let item = NSMenuItem(
                title: candidate.name,
                action: #selector(AppPickerTarget.pick(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = candidate
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let other = NSMenuItem(
            title: "Andere…", action: #selector(AppPickerTarget.other), keyEquivalent: ""
        )
        other.target = target
        menu.addItem(other)
        // popUp runs its own tracking loop and sends the selected item's
        // action before returning; keep the weakly-referenced target alive.
        withExtendedLifetime(target) {
            _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    private static func defaultBrowserBundleID() -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else {
            return nil
        }
        return Bundle(url: url)?.bundleIdentifier
    }

    /// Spec: the Timer itself, Finder, and the default browser are not blockable.
    private static func unblockableBundleIDs() -> Set<String> {
        Set([
            Bundle.main.bundleIdentifier ?? "",
            "com.apple.finder",
            defaultBrowserBundleID() ?? "",
        ])
    }

    /// v15: the essential set is implicitly allowed, so listing those apps
    /// would be redundant — the picker hides them. The default browser stays
    /// pickable: in allowlist mode browsers are governed like any app.
    private static func implicitlyAllowedBundleIDs() -> Set<String> {
        AllowlistRules.essentialBundleIDs.union([Bundle.main.bundleIdentifier ?? ""])
    }

    private func runningUserApps(
        excluded: Set<String>, listed: [BlockedApp]
    ) -> [BlockedApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let name = app.localizedName,
                      !excluded.contains(id),
                      !listed.contains(where: { $0.bundleID == id }) else { return nil }
                return BlockedApp(bundleID: id, name: name)
            }
            .sorted { $0.name < $1.name }
    }

    private func pickAppFromDisk(excluded: Set<String>, add: (BlockedApp) -> Void) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier,
              !excluded.contains(id) else { return }
        add(BlockedApp(bundleID: id, name: url.deletingPathExtension().lastPathComponent))
    }

    // MARK: - Load

    private func load() {
        blockedApps = preferences.blockedApps
        blockedDomains = preferences.blockedDomains
        allowedApps = preferences.allowedApps
        allowedDomains = preferences.allowedDomains
        emergencyApps = preferences.emergencyApps
        emergencyDomains = preferences.emergencyDomains
        emergencyMinutesText = String(preferences.emergencyMinutes)
        shieldEnabled = preferences.focusBlockEnabled
    }
}
