import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TimerCore

extension Notification.Name {
    static let timerSettingsChanged = Notification.Name("timerSettingsChanged")
}

struct SettingsView: View {
    let preferences: Preferences

    @State private var presetTexts: [String] = []
    @State private var focusText = ""
    @State private var breakText = ""
    @State private var longBreakText = ""
    @State private var roundsText = ""
    @State private var volume = 1.0
    @State private var launchAtLogin = false
    @State private var floating = true
    @State private var loginHint: String?
    @State private var blockedApps: [BlockedApp] = []
    @State private var blockedDomains: [String] = []
    @State private var newDomain = ""
    @State private var hotkeyPopover: HotkeyCombo?
    @State private var hotkeyQuickStart: HotkeyCombo?
    @State private var hotkeyHint: String?
    @State private var trackingPaused = false
    @State private var idleText = "5"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Presets (Minuten)") {
                HStack(spacing: 6) {
                    ForEach(0..<6, id: \.self) { index in
                        TextField("", text: presetBinding(index))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .frame(width: 44)
                            .onSubmit(commitPresets)
                    }
                }
            }

            section("Pomodoro") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Fokus (min)")
                        numberField($focusText, commit: commitPomodoro)
                    }
                    GridRow {
                        Text("Pause (min)")
                        numberField($breakText, commit: commitPomodoro)
                    }
                    GridRow {
                        Text("Lange Pause (min)")
                        numberField($longBreakText, commit: commitPomodoro)
                    }
                    GridRow {
                        Text("Runden bis lange Pause")
                        numberField($roundsText, commit: commitPomodoro)
                    }
                }
            }

            section("Alarm") {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.wave.2")
                        .foregroundStyle(.secondary)
                    Slider(value: $volume, in: 0...1)
                        .onChange(of: volume) { newValue in
                            preferences.alarmVolume = newValue
                        }
                    Button("Test") {
                        SoundPlayer.playCompletionChime(volume: preferences.alarmVolume)
                    }
                }
            }

            generalSection

            focusBlockSection

            hotkeysSection

            activitySection
        }
        .padding(20)
        .frame(width: 360)
        .onAppear(perform: load)
    }

    private var generalSection: some View {
        section("Allgemein") {
            Toggle("Beim Anmelden starten", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    guard newValue != LaunchAtLogin.isEnabled else { return }
                    do {
                        try LaunchAtLogin.setEnabled(newValue)
                        loginHint = nil
                    } catch {
                        launchAtLogin = LaunchAtLogin.isEnabled
                        loginHint = "macOS hat das abgelehnt. Manuell: Systemeinstellungen → Allgemein → Anmeldeobjekte → \"+\" → Timer.app."
                    }
                }
            if let hint = loginHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Floating Display", isOn: $floating)
                .onChange(of: floating) { newValue in
                    preferences.floatingEnabled = newValue
                    NotificationCenter.default.post(name: .timerSettingsChanged, object: nil)
                }
        }
    }

    private var focusBlockSection: some View {
        section("Fokus-Block") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(blockedApps, id: \.bundleID) { app in
                    HStack {
                        Text(app.name).font(.system(size: 12))
                        Spacer()
                        Button {
                            blockedApps.removeAll { $0.bundleID == app.bundleID }
                            preferences.blockedApps = blockedApps
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                Menu("App hinzufügen") {
                    ForEach(runningUserApps(), id: \.bundleID) { candidate in
                        Button(candidate.name) {
                            addBlockedApp(candidate)
                        }
                    }
                    Divider()
                    Button("Andere…", action: pickAppFromDisk)
                }
                .menuStyle(.borderlessButton)
                .font(.system(size: 11))

                ForEach(blockedDomains, id: \.self) { domain in
                    HStack {
                        Text(domain).font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Button {
                            blockedDomains.removeAll { $0 == domain }
                            preferences.blockedDomains = blockedDomains
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    TextField("instagram.com", text: $newDomain)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .onSubmit(addDomain)
                    Button("Hinzufügen", action: addDomain)
                        .controlSize(.small)
                }
                Text("Website-Block braucht die Automation-Berechtigung (macOS fragt beim ersten Mal).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hotkeysSection: some View {
        section("Hotkeys") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Popover öffnen")
                    HotkeyRecorderField(combo: hotkeyPopover) { newCombo in
                        guard newCombo == nil || newCombo != hotkeyQuickStart else {
                            hotkeyHint = "Kombination ist schon vergeben."
                            return
                        }
                        hotkeyHint = nil
                        hotkeyPopover = newCombo
                        preferences.hotkeyPopover = newCombo
                        NotificationCenter.default.post(name: .timerSettingsChanged, object: nil)
                    }
                }
                GridRow {
                    Text("Sofort-Start")
                    HotkeyRecorderField(combo: hotkeyQuickStart) { newCombo in
                        guard newCombo == nil || newCombo != hotkeyPopover else {
                            hotkeyHint = "Kombination ist schon vergeben."
                            return
                        }
                        hotkeyHint = nil
                        hotkeyQuickStart = newCombo
                        preferences.hotkeyQuickStart = newCombo
                        NotificationCenter.default.post(name: .timerSettingsChanged, object: nil)
                    }
                }
            }
            if let hint = hotkeyHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var activitySection: some View {
        section("Aktivität") {
            Toggle("Tracking pausieren", isOn: $trackingPaused)
                .onChange(of: trackingPaused) { newValue in
                    preferences.trackingPaused = newValue
                }
            HStack {
                Text("Inaktiv nach (min)")
                numberField($idleText) {
                    if let value = Int(idleText) { preferences.idleThresholdMinutes = value }
                    idleText = String(preferences.idleThresholdMinutes)
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func numberField(_ text: Binding<String>, commit: @escaping () -> Void) -> some View {
        TextField("", text: text)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: 60)
            .onSubmit(commit)
    }

    private func presetBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < presetTexts.count ? presetTexts[index] : "" },
            set: { newValue in
                if index < presetTexts.count {
                    presetTexts[index] = String(newValue.filter(\.isNumber).prefix(3))
                }
            }
        )
    }

    private func load() {
        presetTexts = preferences.presets.map(String.init)
        let config = preferences.pomodoroConfig
        focusText = String(config.focusMinutes)
        breakText = String(config.breakMinutes)
        longBreakText = String(config.longBreakMinutes)
        roundsText = String(config.rounds)
        volume = preferences.alarmVolume
        launchAtLogin = LaunchAtLogin.isEnabled
        floating = preferences.floatingEnabled
        blockedApps = preferences.blockedApps
        blockedDomains = preferences.blockedDomains
        hotkeyPopover = preferences.hotkeyPopover
        hotkeyQuickStart = preferences.hotkeyQuickStart
        trackingPaused = preferences.trackingPaused
        idleText = String(preferences.idleThresholdMinutes)
    }

    // MARK: - Focus block helpers

    private struct AppCandidate {
        let bundleID: String
        let name: String
    }

    private static func defaultBrowserBundleID() -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else {
            return nil
        }
        return Bundle(url: url)?.bundleIdentifier
    }

    private func runningUserApps() -> [AppCandidate] {
        // Spec: the Timer itself, Finder, and the default browser are not blockable.
        let excluded = Set([
            Bundle.main.bundleIdentifier ?? "",
            "com.apple.finder",
            Self.defaultBrowserBundleID() ?? "",
        ])
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let name = app.localizedName,
                      !excluded.contains(id),
                      !blockedApps.contains(where: { $0.bundleID == id }) else { return nil }
                return AppCandidate(bundleID: id, name: name)
            }
            .sorted { $0.name < $1.name }
    }

    private func addBlockedApp(_ candidate: AppCandidate) {
        blockedApps.append(BlockedApp(bundleID: candidate.bundleID, name: candidate.name))
        preferences.blockedApps = blockedApps
    }

    private func pickAppFromDisk() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier else { return }
        // Same guard as the running-apps menu: Timer, Finder, and the
        // default browser are not blockable.
        let excluded = Set([
            Bundle.main.bundleIdentifier ?? "",
            "com.apple.finder",
            Self.defaultBrowserBundleID() ?? "",
        ])
        guard !excluded.contains(id) else { return }
        let name = url.deletingPathExtension().lastPathComponent
        guard !blockedApps.contains(where: { $0.bundleID == id }) else { return }
        blockedApps.append(BlockedApp(bundleID: id, name: name))
        preferences.blockedApps = blockedApps
    }

    private func addDomain() {
        guard let sanitized = Preferences.sanitizeDomain(newDomain),
              !blockedDomains.contains(sanitized) else { return }
        blockedDomains.append(sanitized)
        preferences.blockedDomains = blockedDomains
        newDomain = ""
    }

    private func commitPresets() {
        let values = presetTexts.map { Int($0) ?? 0 }
        guard values.allSatisfy({ $0 >= 1 }) else {
            presetTexts = preferences.presets.map(String.init)
            return
        }
        preferences.presets = values
        presetTexts = preferences.presets.map(String.init)
    }

    private func commitPomodoro() {
        var config = preferences.pomodoroConfig
        if let focus = Int(focusText) { config.focusMinutes = focus }
        if let brk = Int(breakText) { config.breakMinutes = brk }
        if let long = Int(longBreakText) { config.longBreakMinutes = long }
        if let rounds = Int(roundsText) { config.rounds = rounds }
        preferences.pomodoroConfig = config
        let saved = preferences.pomodoroConfig
        focusText = String(saved.focusMinutes)
        breakText = String(saved.breakMinutes)
        longBreakText = String(saved.longBreakMinutes)
        roundsText = String(saved.rounds)
    }
}
