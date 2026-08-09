import SwiftUI
import TimerCore

extension Notification.Name {
    static let timerSettingsChanged = Notification.Name("timerSettingsChanged")
}

struct SettingsView: View {
    let preferences: Preferences
    @ObservedObject var focusMode: FocusModeController

    /// v9: identity of every numeric field, for focus-loss snap-back.
    private enum NumberField: Hashable {
        case preset(Int)
        case pomodoroFocus, pomodoroBreak, pomodoroLongBreak, pomodoroRounds
        case idleThreshold
    }

    /// Clamp ranges mirroring Preferences (values outside are not live-saved).
    private static let minuteRange = 1...720
    private static let roundsRange = 1...12
    private static let idleRange = 1...30

    /// v17: the settings tabs (v18 added "Rechte"). Selection is
    /// per-window-session — the window rebuilds its view on every show(),
    /// so it opens on Timer.
    private enum SettingsTab: CaseIterable {
        case timer, fokus, aktivitaet, allgemein, rechte

        var label: String {
            switch self {
            case .timer: return "Timer"
            case .fokus: return "Fokus"
            case .aktivitaet: return "Aktivität"
            case .allgemein: return "Allgemein"
            case .rechte: return "Rechte"
            }
        }
    }

    @FocusState private var focusedNumberField: NumberField?
    @State private var tab: SettingsTab = .timer
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
    @State private var hotkeyPopover: HotkeyCombo?
    @State private var hotkeyQuickStart: HotkeyCombo?
    @State private var hotkeyExtend: HotkeyCombo?
    @State private var hotkeyHint: String?
    @State private var trackingPaused = false
    @State private var idleText = "5"
    @State private var promotedSitesList: [String] = []
    @State private var newPromotedSite = ""
    @State private var dndEnabled = false
    @State private var dndOnName = ""
    @State private var dndOffName = ""
    @State private var menuBarFormat = MenuBarTimeFormat.standard
    @State private var menuBarIconOnly = false

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $tab) {
                ForEach(SettingsTab.allCases, id: \.self) { pane in
                    Text(pane.label).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ZStack(alignment: .top) {
                tabPane(.timer) {
                    presetsSection
                    pomodoroSection
                    alarmSection
                }
                tabPane(.fokus) {
                    FocusBlockSettingsSection(preferences: preferences)
                    dndSection
                }
                tabPane(.aktivitaet) {
                    activitySection
                }
                tabPane(.allgemein) {
                    generalSection
                    menuBarSection
                    hotkeysSection
                }
                tabPane(.rechte) {
                    PermissionsSettingsSection(
                        preferences: preferences, focusMode: focusMode
                    )
                }
            }
        }
        .padding(20)
        // v18: 400 instead of v17's 360 — five segments need the room, and
        // the permission rows carry a badge plus two buttons per line.
        .frame(width: 400)
        // v17: switching tabs drops field focus, so pending numeric input
        // runs through the same snap-back as any other focus loss.
        .onChange(of: tab) { _ in focusedNumberField = nil }
        // v9: leaving a numeric field snaps pending (unsaved) input back to
        // the stored value — in-range input was already live-saved.
        .onChange(of: focusedNumberField) { _ in reloadNumberTexts() }
        .onAppear(perform: load)
    }

    /// v17: one settings tab. All four panes stay mounted in the ZStack —
    /// hidden panes keep their layout size, so the window height derived by
    /// SettingsWindowController fits the tallest tab and the per-tab
    /// ScrollView only ever scrolls as overflow safety (e.g. grown lists).
    @ViewBuilder private func tabPane(
        _ pane: SettingsTab, @ViewBuilder content: () -> some View
    ) -> some View {
        let scroll = ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if tab == pane {
            scroll
        } else {
            scroll.hidden().disabled(true)
        }
    }

    private var presetsSection: some View {
        section("Presets (Minuten)") {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    TextField("", text: liveSaving(
                        presetBinding(index), range: Self.minuteRange,
                        store: { storePreset(index, value: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 44)
                    .focused($focusedNumberField, equals: .preset(index))
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
                    numberField(
                        $focusText, field: .pomodoroFocus, range: Self.minuteRange,
                        store: { storePomodoro(\.focusMinutes, value: $0) },
                        commit: commitPomodoro
                    )
                }
                GridRow {
                    Text("Pause (min)")
                    numberField(
                        $breakText, field: .pomodoroBreak, range: Self.minuteRange,
                        store: { storePomodoro(\.breakMinutes, value: $0) },
                        commit: commitPomodoro
                    )
                }
                GridRow {
                    Text("Lange Pause (min)")
                    numberField(
                        $longBreakText, field: .pomodoroLongBreak, range: Self.minuteRange,
                        store: { storePomodoro(\.longBreakMinutes, value: $0) },
                        commit: commitPomodoro
                    )
                }
                GridRow {
                    Text("Runden bis lange Pause")
                    numberField(
                        $roundsText, field: .pomodoroRounds, range: Self.roundsRange,
                        store: { storePomodoro(\.rounds, value: $0) },
                        commit: commitPomodoro
                    )
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

    private var menuBarSection: some View {
        section("Menüleiste") {
            HStack {
                Text("Zeitformat")
                Picker("", selection: $menuBarFormat) {
                    Text("Standard").tag(MenuBarTimeFormat.standard)
                    Text("Kompakt").tag(MenuBarTimeFormat.compact)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(menuBarIconOnly)
                .onChange(of: menuBarFormat) { newValue in
                    preferences.menuBarTimeFormat = newValue
                    NotificationCenter.default.post(name: .timerSettingsChanged, object: nil)
                }
            }
            Toggle("Nur Symbol", isOn: $menuBarIconOnly)
                .onChange(of: menuBarIconOnly) { newValue in
                    preferences.menuBarShowTime = !newValue
                    NotificationCenter.default.post(name: .timerSettingsChanged, object: nil)
                }
            if menuBarIconOnly {
                Text("Ohne Zeit in der Menüleiste empfiehlt sich das Floating Display.")
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
                    // v8: lets the activity tracker stop/start its timers.
                    NotificationCenter.default.post(name: .timerSettingsChanged, object: nil)
                }
            HStack {
                Text("Inaktiv nach (min)")
                numberField(
                    $idleText, field: .idleThreshold, range: Self.idleRange,
                    store: { value in
                        preferences.idleThresholdMinutes = value
                        return preferences.idleThresholdMinutes
                    },
                    commit: {
                        if let value = Int(idleText) { preferences.idleThresholdMinutes = value }
                        idleText = String(preferences.idleThresholdMinutes)
                    }
                )
            }
            Text("Eigene Einträge (Websites)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            promotedSiteList
            Text("Diese Websites erscheinen in der Aktivität als eigene Einträge.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// v13: the promoted-websites list — the block-list domain UI pattern
    /// (removable rows + field + add button, live write-through).
    private var promotedSiteList: some View {
        Group {
            ForEach(promotedSitesList, id: \.self) { domain in
                HStack {
                    Text(domain).font(.system(size: 12, design: .monospaced))
                    Spacer()
                    Button {
                        removePromotedSite(domain)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            HStack {
                TextField("tiktok.com", text: $newPromotedSite)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit(commitPromotedSite)
                Button("Hinzufügen", action: commitPromotedSite)
                    .controlSize(.small)
            }
        }
    }

    /// Removal writes through Preferences and re-reads what persisted — an
    /// emptied list stays empty (the v13 never-set vs. cleared split).
    private func removePromotedSite(_ domain: String) {
        var sites = promotedSitesList
        sites.removeAll { $0 == domain }
        preferences.promotedSites = sites
        promotedSitesList = preferences.promotedSites
    }

    /// Single commit path for Enter and the button: Preferences sanitizes,
    /// dedupes, and stores; the list re-reads what actually persisted
    /// (write-through verification) and the field only clears on success.
    private func commitPromotedSite() {
        let stored = preferences.addPromotedSite(newPromotedSite)
        promotedSitesList = preferences.promotedSites
        if stored != nil { newPromotedSite = "" }
    }

    private var dndSection: some View {
        section("Nicht stören") {
            Toggle("Fokus-Modus koppeln", isOn: $dndEnabled)
                .disabled(!focusMode.shortcutsAvailable)
                .onChange(of: dndEnabled) { newValue in
                    preferences.dndEnabled = newValue
                }
            if focusMode.shortcutsAvailable {
                dndShortcutPickers
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

    /// Dropdowns over the user's existing Shortcuts (`shortcuts list`), so
    /// nobody has to type exact names anymore (v8).
    private var dndShortcutPickers: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Kurzbefehl an")
                dndPicker(selection: $dndOnName) { preferences.dndShortcutOn = $0 }
            }
            GridRow {
                Text("Kurzbefehl aus")
                dndPicker(selection: $dndOffName) { preferences.dndShortcutOff = $0 }
            }
            GridRow {
                Text("")
                Button("Liste aktualisieren") { focusMode.refreshShortcutList() }
                    .controlSize(.small)
            }
        }
    }

    private func dndPicker(
        selection: Binding<String>, commit: @escaping (String) -> Void
    ) -> some View {
        Picker("", selection: selection) {
            ForEach(dndOptions(current: selection.wrappedValue), id: \.self) { name in
                Text(name).tag(name)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 200)
        .onChange(of: selection.wrappedValue) { newValue in
            commit(newValue)
        }
    }

    /// The listed shortcuts, with the stored selection prepended when it is
    /// not (or not yet) in the list — the picker always shows a valid row.
    private func dndOptions(current: String) -> [String] {
        var options = focusMode.availableShortcuts
        if !current.isEmpty && !options.contains(current) {
            options.insert(current, at: 0)
        }
        return options
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

    private func numberField(
        _ text: Binding<String>, field: NumberField, range: ClosedRange<Int>,
        store: @escaping (Int) -> Int, commit: @escaping () -> Void
    ) -> some View {
        TextField("", text: liveSaving(text, range: range, store: store))
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: 60)
            .focused($focusedNumberField, equals: field)
            .onSubmit(commit)
    }

    /// v9 live-save: every keystroke that parses into the clamp range is
    /// written to Preferences immediately and the field re-reads what stuck
    /// (write-through); anything else stays pending in the field until focus
    /// loss snaps it back to the stored value. `store` writes one value and
    /// returns the stored result.
    private func liveSaving(
        _ text: Binding<String>, range: ClosedRange<Int>, store: @escaping (Int) -> Int
    ) -> Binding<String> {
        Binding(
            get: { text.wrappedValue },
            set: { newValue in
                text.wrappedValue = newValue
                // Re-read: the inner binding may have filtered the input.
                guard let value = Int(text.wrappedValue), range.contains(value) else { return }
                text.wrappedValue = String(store(value))
            }
        )
    }

    private func storePreset(_ index: Int, value: Int) -> Int {
        var values = preferences.presets
        guard values.indices.contains(index) else { return value }
        values[index] = value
        preferences.presets = values
        return preferences.presets[index]
    }

    private func storePomodoro(
        _ keyPath: WritableKeyPath<PomodoroConfig, Int>, value: Int
    ) -> Int {
        var config = preferences.pomodoroConfig
        config[keyPath: keyPath] = value
        preferences.pomodoroConfig = config
        return preferences.pomodoroConfig[keyPath: keyPath]
    }

    /// Focus-change snap-back: all numeric fields re-read their stored
    /// values, discarding pending input that never parsed into range.
    private func reloadNumberTexts() {
        presetTexts = preferences.presets.map(String.init)
        let config = preferences.pomodoroConfig
        focusText = String(config.focusMinutes)
        breakText = String(config.breakMinutes)
        longBreakText = String(config.longBreakMinutes)
        roundsText = String(config.rounds)
        idleText = String(preferences.idleThresholdMinutes)
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
        reloadNumberTexts()
        volume = preferences.alarmVolume
        launchAtLogin = LaunchAtLogin.isEnabled
        loginStatus = LaunchAtLogin.status
        floating = preferences.floatingEnabled
        hotkeyPopover = preferences.hotkeyPopover
        hotkeyQuickStart = preferences.hotkeyQuickStart
        hotkeyExtend = preferences.hotkeyExtend
        trackingPaused = preferences.trackingPaused
        promotedSitesList = preferences.promotedSites
        dndEnabled = preferences.dndEnabled
        dndOnName = preferences.dndShortcutOn
        dndOffName = preferences.dndShortcutOff
        focusMode.refreshShortcutList()
        menuBarFormat = preferences.menuBarTimeFormat
        menuBarIconOnly = !preferences.menuBarShowTime
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
