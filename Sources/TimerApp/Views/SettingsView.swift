import SwiftUI
import TimerCore

extension Notification.Name {
    static let timerSettingsChanged = Notification.Name("timerSettingsChanged")
    /// The interface language changed: views that are built once (the popover)
    /// have to be rebuilt, since they hold already-resolved strings.
    static let timerLanguageChanged = Notification.Name("timerLanguageChanged")
}

struct SettingsView: View {
    let preferences: Preferences
    @ObservedObject var focusMode: FocusModeController
    /// v21: passed straight through to the "Rechte" tab.
    let onTestFullscreenBlock: FullscreenBlockTester?

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
            case .fokus: return tr("Fokus", "Focus")
            case .aktivitaet: return tr("Aktivität", "Activity")
            case .allgemein: return tr("Allgemein", "General")
            case .rechte: return tr("Rechte", "Permissions")
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
    @State private var hotkeyEmergency: HotkeyCombo?
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
    @State private var language = AppLanguage.system

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
                    languageSection
                    generalSection
                    menuBarSection
                    hotkeysSection
                }
                tabPane(.rechte) {
                    PermissionsSettingsSection(
                        preferences: preferences, focusMode: focusMode,
                        onTestFullscreenBlock: onTestFullscreenBlock
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
        section(tr("Presets (Minuten)", "Presets (minutes)")) {
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
                    Text(tr("Fokus (min)", "Focus (min)"))
                    numberField(
                        $focusText, field: .pomodoroFocus, range: Self.minuteRange,
                        store: { storePomodoro(\.focusMinutes, value: $0) },
                        commit: commitPomodoro
                    )
                }
                GridRow {
                    Text(tr("Pause (min)", "Break (min)"))
                    numberField(
                        $breakText, field: .pomodoroBreak, range: Self.minuteRange,
                        store: { storePomodoro(\.breakMinutes, value: $0) },
                        commit: commitPomodoro
                    )
                }
                GridRow {
                    Text(tr("Lange Pause (min)", "Long break (min)"))
                    numberField(
                        $longBreakText, field: .pomodoroLongBreak, range: Self.minuteRange,
                        store: { storePomodoro(\.longBreakMinutes, value: $0) },
                        commit: commitPomodoro
                    )
                }
                GridRow {
                    Text(tr("Runden bis lange Pause", "Rounds until long break"))
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
        section(tr("Alarm", "Alarm")) {
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
        section(tr("Allgemein", "General")) {
            Toggle(tr("Beim Anmelden starten", "Start at login"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    guard newValue != LaunchAtLogin.isEnabled else { return }
                    do {
                        try LaunchAtLogin.setEnabled(newValue)
                        loginHint = nil
                    } catch {
                        loginHint = tr("macOS hat das abgelehnt. Manuell: Systemeinstellungen → Allgemein → Anmeldeobjekte → \"+\" → Timer.app.", "macOS refused. Manually: System Settings → General → Login Items → \"+\" → Timer.app.")
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
            Toggle(tr("Floating Display", "Floating display"), isOn: $floating)
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
            loginStatusText(tr("Status: Aktiv", "Status: active"))
        case .activeLaunchAgent:
            loginStatusText(tr("Status: Aktiv (LaunchAgent)", "Status: active (LaunchAgent)"))
        case .requiresApproval:
            loginStatusText(tr("Status: Wartet auf Freigabe", "Status: waiting for approval"))
            Button(tr("Systemeinstellungen öffnen", "Open System Settings")) {
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

    /// The interface language. "System" is the default and follows macOS, so
    /// nobody has to find this — the explicit choice exists for a German user
    /// on an English system, and for handing the app to someone who is not.
    private var languageSection: some View {
        section(tr("Sprache", "Language")) {
            Picker("", selection: $language) {
                Text(tr("System", "System")).tag(AppLanguage.system)
                Text("Deutsch").tag(AppLanguage.german)
                Text("English").tag(AppLanguage.english)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: language) { newValue in
                preferences.language = newValue
                L10n.refresh(preferences: preferences)
                // The settings window re-renders itself through this very
                // state change; everything else is rebuilt by the observer in
                // StatusBarController.
                NotificationCenter.default.post(name: .timerLanguageChanged, object: nil)
                NotificationCenter.default.post(name: .timerSettingsChanged, object: nil)
            }
        }
    }

    private var menuBarSection: some View {
        section(tr("Menüleiste", "Menu bar")) {
            HStack {
                Text(tr("Zeitformat", "Time format"))
                Picker("", selection: $menuBarFormat) {
                    Text(tr("Standard", "Standard")).tag(MenuBarTimeFormat.standard)
                    Text(tr("Kompakt", "Compact")).tag(MenuBarTimeFormat.compact)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(menuBarIconOnly)
                .onChange(of: menuBarFormat) { newValue in
                    preferences.menuBarTimeFormat = newValue
                    NotificationCenter.default.post(name: .timerSettingsChanged, object: nil)
                }
            }
            Toggle(tr("Nur Symbol", "Icon only"), isOn: $menuBarIconOnly)
                .onChange(of: menuBarIconOnly) { newValue in
                    preferences.menuBarShowTime = !newValue
                    NotificationCenter.default.post(name: .timerSettingsChanged, object: nil)
                }
            if menuBarIconOnly {
                Text(tr("Ohne Zeit in der Menüleiste empfiehlt sich das Floating Display.", "Without the time in the menu bar, the floating display is worth turning on."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hotkeysSection: some View {
        section(tr("Hotkeys", "Hotkeys")) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text(tr("Popover öffnen", "Open popover"))
                    HotkeyRecorderField(combo: hotkeyPopover) { newCombo in
                        assignHotkey(newCombo, conflicts: [hotkeyQuickStart, hotkeyExtend]) {
                            hotkeyPopover = $0
                            preferences.hotkeyPopover = $0
                        }
                    }
                }
                GridRow {
                    Text(tr("Sofort-Start", "Quick start"))
                    HotkeyRecorderField(combo: hotkeyQuickStart) { newCombo in
                        assignHotkey(newCombo, conflicts: [hotkeyPopover, hotkeyExtend]) {
                            hotkeyQuickStart = $0
                            preferences.hotkeyQuickStart = $0
                        }
                    }
                }
                GridRow {
                    Text(tr("Verlängern (+5 min)", "Extend (+5 min)"))
                    HotkeyRecorderField(combo: hotkeyExtend) { newCombo in
                        assignHotkey(
                            newCombo, conflicts: [hotkeyPopover, hotkeyQuickStart, hotkeyEmergency]
                        ) {
                            hotkeyExtend = $0
                            preferences.hotkeyExtend = $0
                        }
                    }
                }
                GridRow {
                    Text(tr("Notfall-Modus starten", "Start emergency mode"))
                    HotkeyRecorderField(combo: hotkeyEmergency) { newCombo in
                        assignHotkey(
                            newCombo, conflicts: [hotkeyPopover, hotkeyQuickStart, hotkeyExtend]
                        ) {
                            hotkeyEmergency = $0
                            preferences.hotkeyEmergency = $0
                        }
                    }
                }
            }
            Text(tr("Der Notfall-Hotkey startet sofort mit der eingestellten Dauer.", "The emergency hotkey starts immediately, with the duration set below."))
                .font(.caption2)
                .foregroundStyle(.secondary)
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
            hotkeyHint = tr("Kombination ist schon vergeben.", "That combination is already taken.")
            return
        }
        hotkeyHint = nil
        commit(combo)
        NotificationCenter.default.post(name: .timerSettingsChanged, object: nil)
    }

    private var activitySection: some View {
        section(tr("Aktivität", "Activity")) {
            Toggle(tr("Tracking pausieren", "Pause tracking"), isOn: $trackingPaused)
                .onChange(of: trackingPaused) { newValue in
                    preferences.trackingPaused = newValue
                    // v8: lets the activity tracker stop/start its timers.
                    NotificationCenter.default.post(name: .timerSettingsChanged, object: nil)
                }
            HStack {
                Text(tr("Inaktiv nach (min)", "Idle after (min)"))
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
            Text(tr("Eigene Einträge (Websites)", "Own entries (websites)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            promotedSiteList
            Text(tr("Diese Websites erscheinen in der Aktivität als eigene Einträge.", "These websites appear as their own rows in the activity view."))
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
                Button(tr("Hinzufügen", "Add"), action: commitPromotedSite)
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
        section(tr("Nicht stören", "Do Not Disturb")) {
            Toggle(tr("Fokus-Modus koppeln", "Couple the Focus mode"), isOn: $dndEnabled)
                .disabled(!focusMode.shortcutsAvailable)
                .onChange(of: dndEnabled) { newValue in
                    preferences.dndEnabled = newValue
                }
            if focusMode.shortcutsAvailable {
                dndShortcutPickers
                Text(tr("Lege in der Kurzbefehle-App zwei Kurzbefehle an: 'Timer Fokus an' → Fokus 'Nicht stören' aktivieren, 'Timer Fokus aus' → deaktivieren.", "Create two shortcuts in the Shortcuts app: 'Timer Fokus an' → turn the 'Do Not Disturb' focus on, 'Timer Fokus aus' → turn it off."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(tr("Testen: an", "Test: on")) { focusMode.test(on: true) }
                        .controlSize(.small)
                    Button(tr("Testen: aus", "Test: off")) { focusMode.test(on: false) }
                        .controlSize(.small)
                }
                if let status = focusMode.statusMessage {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(tr("Benötigt macOS 12+ (Kurzbefehle).", "Requires macOS 12+ (Shortcuts)."))
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
                Text(tr("Kurzbefehl an", "Shortcut on"))
                dndPicker(selection: $dndOnName) { preferences.dndShortcutOn = $0 }
            }
            GridRow {
                Text(tr("Kurzbefehl aus", "Shortcut off"))
                dndPicker(selection: $dndOffName) { preferences.dndShortcutOff = $0 }
            }
            GridRow {
                Text("")
                Button(tr("Liste aktualisieren", "Refresh list")) { focusMode.refreshShortcutList() }
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
        language = preferences.language
        reloadNumberTexts()
        volume = preferences.alarmVolume
        launchAtLogin = LaunchAtLogin.isEnabled
        loginStatus = LaunchAtLogin.status
        floating = preferences.floatingEnabled
        hotkeyPopover = preferences.hotkeyPopover
        hotkeyQuickStart = preferences.hotkeyQuickStart
        hotkeyExtend = preferences.hotkeyExtend
        hotkeyEmergency = preferences.hotkeyEmergency
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
