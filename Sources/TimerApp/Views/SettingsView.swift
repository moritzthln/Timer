import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TimerCore

extension Notification.Name {
    static let timerSettingsChanged = Notification.Name("timerSettingsChanged")
}

struct SettingsView: View {
    let preferences: Preferences
    @ObservedObject var focusMode: FocusModeController

    @State private var presetTexts: [String] = []
    @State private var focusText = ""
    @State private var breakText = ""
    @State private var longBreakText = ""
    @State private var roundsText = ""
    @State private var volume = 1.0
    @State private var launchAtLogin = false
    @State private var loginStatus: LaunchAtLogin.Status = .inactive
    @State private var floating = true
    @State private var loginHint: String?
    @State private var blockedApps: [BlockedApp] = []
    @State private var blockedDomains: [String] = []
    @State private var newDomain = ""
    @State private var shieldEnabled = false
    @State private var hotkeyPopover: HotkeyCombo?
    @State private var hotkeyQuickStart: HotkeyCombo?
    @State private var hotkeyExtend: HotkeyCombo?
    @State private var hotkeyHint: String?
    @State private var trackingPaused = false
    @State private var idleText = "5"
    @State private var dndEnabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                presetsSection
                pomodoroSection
                alarmSection
                generalSection
                focusBlockSection
                hotkeysSection
                activitySection
                dndSection
            }
            .padding(20)
        }
        .frame(width: 360, height: 700)
        .onAppear(perform: load)
    }

    private var presetsSection: some View {
        section("Presets (Minuten)") {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    TextField("", text: presetBinding(index))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .frame(width: 44)
                        .onSubmit(commitPresets)
                }
            }
        }
    }

    private var pomodoroSection: some View {
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
    }

    private var alarmSection: some View {
        section("Alarm") {
            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(.secondary)
                Slider(value: $volume, in: 0...1)
                    .onChange(of: volume) { newValue in
                        preferences.alarmVolume = newValue
                    }
                Button("Test") {
                    SoundPlayer.playMajorAlarm(volume: preferences.alarmVolume)
                }
            }
        }
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
                        loginHint = "macOS hat das abgelehnt. Manuell: Systemeinstellungen → Allgemein → Anmeldeobjekte → \"+\" → Timer.app."
                    }
                    launchAtLogin = LaunchAtLogin.isEnabled
                    loginStatus = LaunchAtLogin.status
                }
            loginStatusLine
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

    /// Live status under the login toggle; the approval state deep-links to
    /// the Login Items pane.
    @ViewBuilder private var loginStatusLine: some View {
        switch loginStatus {
        case .active:
            loginStatusText("Status: Aktiv")
        case .activeLaunchAgent:
            loginStatusText("Status: Aktiv (LaunchAgent)")
        case .requiresApproval:
            loginStatusText("Status: Wartet auf Freigabe")
            Button("Systemeinstellungen öffnen") {
                LaunchAtLogin.openLoginItemsSettings()
            }
            .controlSize(.small)
        case .inactive:
            EmptyView()
        }
    }

    private func loginStatusText(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var focusBlockSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            focusBlockHeader
            VStack(alignment: .leading, spacing: 4) {
                blockedAppList
                blockedDomainList
                focusBlockCaptions
            }
        }
    }

    /// Header row doubles as live state display, so the settings window
    /// itself reveals whether the shield would block right now.
    private var focusBlockHeader: some View {
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

    private var blockedAppList: some View {
        Group {
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
            // v7: plain bordered button + programmatic NSMenu; the previous
            // SwiftUI Menu with .menuStyle(.borderlessButton) never opened.
            Button("App hinzufügen", action: showAppPicker)
                .controlSize(.small)
        }
    }

    private var blockedDomainList: some View {
        Group {
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
                    .onSubmit(commitDomains)
                Button("Hinzufügen", action: commitDomains)
                    .controlSize(.small)
            }
        }
    }

    private var focusBlockCaptions: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Aktiv während Fokus-Sessions, wenn das Schild im Popover an ist.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Website-Block braucht die Automation-Berechtigung (macOS fragt beim ersten Mal).")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hotkeysSection: some View {
        section("Hotkeys") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Popover öffnen")
                    HotkeyRecorderField(combo: hotkeyPopover) { newCombo in
                        assignHotkey(newCombo, conflicts: [hotkeyQuickStart, hotkeyExtend]) {
                            hotkeyPopover = $0
                            preferences.hotkeyPopover = $0
                        }
                    }
                }
                GridRow {
                    Text("Sofort-Start")
                    HotkeyRecorderField(combo: hotkeyQuickStart) { newCombo in
                        assignHotkey(newCombo, conflicts: [hotkeyPopover, hotkeyExtend]) {
                            hotkeyQuickStart = $0
                            preferences.hotkeyQuickStart = $0
                        }
                    }
                }
                GridRow {
                    Text("Verlängern (+5 min)")
                    HotkeyRecorderField(combo: hotkeyExtend) { newCombo in
                        assignHotkey(newCombo, conflicts: [hotkeyPopover, hotkeyQuickStart]) {
                            hotkeyExtend = $0
                            preferences.hotkeyExtend = $0
                        }
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

    /// Shared recorder commit: rejects combos already used by another row,
    /// stores via `commit`, and lets the running app re-register.
    private func assignHotkey(
        _ combo: HotkeyCombo?, conflicts: [HotkeyCombo?], commit: (HotkeyCombo?) -> Void
    ) {
        if let combo, conflicts.contains(combo) {
            hotkeyHint = "Kombination ist schon vergeben."
            return
        }
        hotkeyHint = nil
        commit(combo)
        NotificationCenter.default.post(name: .timerSettingsChanged, object: nil)
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

    private var dndSection: some View {
        section("Nicht stören") {
            Toggle("Fokus-Modus koppeln", isOn: $dndEnabled)
                .disabled(!focusMode.shortcutsAvailable)
                .onChange(of: dndEnabled) { newValue in
                    preferences.dndEnabled = newValue
                }
            if focusMode.shortcutsAvailable {
                Text("Lege in der Kurzbefehle-App zwei Kurzbefehle an: 'Timer Fokus an' → Fokus 'Nicht stören' aktivieren, 'Timer Fokus aus' → deaktivieren.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Testen: an") { focusMode.test(on: true) }
                        .controlSize(.small)
                    Button("Testen: aus") { focusMode.test(on: false) }
                        .controlSize(.small)
                }
                if let status = focusMode.statusMessage {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Benötigt macOS 12+ (Kurzbefehle).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
        loginStatus = LaunchAtLogin.status
        floating = preferences.floatingEnabled
        blockedApps = preferences.blockedApps
        blockedDomains = preferences.blockedDomains
        shieldEnabled = preferences.focusBlockEnabled
        hotkeyPopover = preferences.hotkeyPopover
        hotkeyQuickStart = preferences.hotkeyQuickStart
        hotkeyExtend = preferences.hotkeyExtend
        trackingPaused = preferences.trackingPaused
        idleText = String(preferences.idleThresholdMinutes)
        dndEnabled = preferences.dndEnabled
    }

    // MARK: - Focus block helpers

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
    private func showAppPicker() {
        let menu = NSMenu()
        let target = AppPickerTarget(
            onPick: { addBlockedApp($0) },
            onOther: { pickAppFromDisk() }
        )
        for candidate in runningUserApps() {
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

    private func runningUserApps() -> [BlockedApp] {
        let excluded = Self.unblockableBundleIDs()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let name = app.localizedName,
                      !excluded.contains(id),
                      !blockedApps.contains(where: { $0.bundleID == id }) else { return nil }
                return BlockedApp(bundleID: id, name: name)
            }
            .sorted { $0.name < $1.name }
    }

    /// Commits through Preferences (dedupe + arm-on-first-entry live there)
    /// and re-reads the stored state so the list shows what actually stuck.
    private func addBlockedApp(_ app: BlockedApp) {
        preferences.addBlockedApp(app)
        blockedApps = preferences.blockedApps
        shieldEnabled = preferences.focusBlockEnabled
    }

    private func pickAppFromDisk() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier,
              !Self.unblockableBundleIDs().contains(id) else { return }
        addBlockedApp(BlockedApp(bundleID: id, name: url.deletingPathExtension().lastPathComponent))
    }

    /// Single commit path for Enter and the button: Preferences sanitizes,
    /// dedupes, and stores; the list re-reads what actually persisted
    /// (write-through verification) and the field only clears on success.
    private func commitDomains() {
        let stored = preferences.addBlockedDomain(newDomain)
        blockedDomains = preferences.blockedDomains
        shieldEnabled = preferences.focusBlockEnabled
        if stored != nil { newDomain = "" }
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
