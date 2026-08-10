import AppKit
import Combine
import SwiftUI
import TimerCore

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let engine: TimerEngine
    private let preferences: Preferences
    private let rightClickMenu = NSMenu()
    private let floatingController: FloatingPanelController
    private let settingsController: SettingsWindowController
    private let stats = StatsStore()
    private let focusBlock: FocusBlockController
    private let focusMode: FocusModeController
    /// v24: the emergency session and its one-second ticker.
    private let emergency: EmergencyController
    private let statsWindow: StatsWindowController
    private let hotkeys = HotkeyManager()
    private let activityStore = ActivityStore(directory: ActivityStore.defaultDirectory())
    private let focusLog = FocusLog(directory: FocusLog.defaultDirectory())
    private var activityTracker: ActivityTrackerController?
    private var cancellable: AnyCancellable?
    private var emergencyCancellable: AnyCancellable?
    /// The emergency state the focus block was last told about, so the block
    /// only reconciles on real transitions instead of on every tick.
    private var emergencyBlocking = false

    init(engine: TimerEngine, preferences: Preferences) {
        self.engine = engine
        self.preferences = preferences
        floatingController = FloatingPanelController(engine: engine, preferences: preferences)
        focusMode = FocusModeController(preferences: preferences)
        emergency = EmergencyController(preferences: preferences)
        settingsController = SettingsWindowController(preferences: preferences, focusMode: focusMode)
        focusBlock = FocusBlockController(preferences: preferences)
        statsWindow = StatsWindowController(
            stats: stats, activity: activityStore, focusLog: focusLog,
            liveFocusStart: { [weak engine] in engine?.activeFocusStart },
            // v13: read live so settings edits reach the next render/reopen.
            promotedSites: { preferences.promotedSites }
        )
        activityTracker = ActivityTrackerController(store: activityStore, preferences: preferences)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        wireEngineCallbacks()
        wireEmergency()
        wireHotkeys()
        wireDiagnostics()
        configurePopover()
        configureStatusItem()
        observeSettingsChanges()
        refresh()
    }

    // MARK: - Setup

    private func wireEngineCallbacks() {
        engine.onFocusSegmentEnded = { [weak self] segment in
            self?.stats.add(focusFrom: segment.start, to: segment.end)
            // v10: also log the raw interval for the timeline focus traces.
            self?.focusLog.append(start: segment.start, end: segment.end)
        }

        cancellable = engine.objectWillChange.sink { [weak self] _ in
            // objectWillChange fires before mutation; refresh after it lands.
            DispatchQueue.main.async {
                guard let self else { return }
                self.refresh()
                // Keep an open popover in step with its content height, so a
                // phase change cannot drift it away from the status item.
                if self.popover.isShown { self.sizePopoverToContent() }
                self.focusBlock.update(phase: self.engine.phase)
                self.focusMode.update(phase: self.engine.phase)
            }
        }

        engine.onFinish = { [weak self] in
            guard let self else { return }
            self.showPopover()
            if self.preferences.soundEnabled {
                SoundPlayer.playMajorAlarm(volume: self.preferences.alarmVolume)
            }
        }

        engine.onPhaseChange = { [weak self] landed in
            guard let self else { return }
            self.showPopover()
            guard self.preferences.soundEnabled else { return }
            // Landing in focus means a break just ended (gentle nudge back to
            // work); landing in a break means a focus phase was completed.
            if case .pomodoro(phase: .focus, _) = landed {
                SoundPlayer.playMinorChime(volume: self.preferences.alarmVolume)
            } else {
                SoundPlayer.playMajorAlarm(volume: self.preferences.alarmVolume)
            }
        }
    }

    /// v24: the emergency drives the same three things the engine does — menu
    /// bar, popover size, focus block — plus the chime when it runs out. The
    /// block is only told on real transitions; the per-second ticks just
    /// repaint. A session restored from disk (relaunch) engages here too.
    private func wireEmergency() {
        focusBlock.emergencyActive = { [weak emergency] in emergency?.isActive ?? false }
        emergency.onTimeout = { [weak self] in
            guard let self, self.preferences.soundEnabled else { return }
            SoundPlayer.playMajorAlarm(volume: self.preferences.alarmVolume)
        }
        emergencyCancellable = emergency.objectWillChange.sink { [weak self] _ in
            // objectWillChange fires before mutation; react after it lands.
            DispatchQueue.main.async { self?.emergencyDidChange() }
        }
        emergencyDidChange()
    }

    private func emergencyDidChange() {
        refresh()
        // The banner and the start panel change the popover's height.
        if popover.isShown { sizePopoverToContent() }
        guard emergency.isActive != emergencyBlocking else { return }
        emergencyBlocking = emergency.isActive
        focusBlock.updateEmergency()
    }

    private func wireHotkeys() {
        hotkeys.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .openPopover:
                self.showPopover()
            case .quickStart:
                self.quickStart()
            case .extend:
                // Only meaningful while running/paused; no-ops otherwise.
                self.engine.extend(minutes: 5)
            case .emergency:
                // Starts with the stored default duration; a running session
                // is never restarted (that would extend it silently).
                guard !self.emergency.isActive else { return }
                self.emergency.start(minutes: self.preferences.emergencyMinutes)
                self.showPopover()
            }
        }
        hotkeys.apply(
            popover: preferences.hotkeyPopover,
            quickStart: preferences.hotkeyQuickStart,
            extend: preferences.hotkeyExtend,
            emergency: preferences.hotkeyEmergency
        )
    }

    /// v21: the "Rechte" tab's fullscreen-block test. Assigned here instead of
    /// passed into the settings window, because the focus block that owns the
    /// ladder is initialized in the same init and cannot be captured earlier.
    private func wireDiagnostics() {
        settingsController.onTestFullscreenBlock = { [weak self] report in
            self?.focusBlock.testFullscreenBlock(report: report)
        }
    }

    private func configurePopover() {
        popover.contentViewController = NSHostingController(
            rootView: TimerView(
                engine: engine, emergency: emergency, preferences: preferences,
                onOpenSettings: { [weak self] in self?.openSettings() },
                onToggleFloating: { [weak self] in self?.toggleFloating() },
                onOpenStats: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.statsWindow.show()
                }
            )
        )
        popover.behavior = .transient
    }

    private func configureStatusItem() {
        rightClickMenu.addItem(
            NSMenuItem(
                title: "Timer beenden",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: ""
            )
        )

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
    }

    private func observeSettingsChanges() {
        NotificationCenter.default.addObserver(
            forName: .timerSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.floatingController.updateVisibility()
            self?.hotkeys.apply(
                popover: self?.preferences.hotkeyPopover ?? nil,
                quickStart: self?.preferences.hotkeyQuickStart ?? nil,
                extend: self?.preferences.hotkeyExtend ?? nil,
                emergency: self?.preferences.hotkeyEmergency ?? nil
            )
            self?.refresh()
        }
    }

    /// ⌘Q closes the popover instead of quitting (user request): the app is a
    /// background tracker, and a reflexive ⌘Q used to end the session, the
    /// activity recording and the block in one keystroke. Quitting stays in
    /// both menus, deliberately without a shortcut.
    func closePopover() {
        popover.performClose(nil)
    }

    // MARK: - Activity tracking

    /// Final activity flush + best-effort Focus-mode off on quit; v16 also
    /// unhides everything the focus block hid (v18: and takes the cover
    /// overlay down), so nothing stays invisible or covered after the Timer
    /// is gone.
    func prepareForTermination() {
        activityTracker?.flush()
        focusMode.deactivateForTermination()
        focusBlock.restoreBlockedApps()
    }

    // MARK: - Hotkey actions

    private func quickStart() {
        switch engine.phase {
        case .idle:
            engine.start(minutes: preferences.lastMinutes)
        case .running:
            engine.pause()
        case .paused:
            engine.resume()
        case .finished:
            engine.dismissFinished()
            engine.start(minutes: preferences.lastMinutes)
        }
    }

    // MARK: - Windows

    private func openSettings() {
        popover.performClose(nil)
        settingsController.show()
    }

    private func toggleFloating() {
        preferences.floatingEnabled.toggle()
        floatingController.updateVisibility()
    }

    // MARK: - Click handling

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = rightClickMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        // The popover has to know its final size BEFORE it is placed: NSPopover
        // anchors the window and then keeps its bottom-left origin, so a height
        // that only settles after the SwiftUI layout pass drags the top edge
        // away from the status item. That was the "opens centimetres too low"
        // report; a nudge afterwards fixed the position but was visible as a
        // jump, so the size is pinned up front instead.
        sizePopoverToContent()
        // Accessory apps must activate, otherwise the text field gets no focus.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// Lays the SwiftUI content out and hands the popover that exact size.
    /// Also called while the popover is open, because the idle, running and
    /// finished views differ in height.
    private func sizePopoverToContent() {
        guard let hosting = popover.contentViewController else { return }
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.view.fittingSize
        guard size.width > 0, size.height > 0, size != popover.contentSize else { return }
        popover.contentSize = size
    }

    // MARK: - Menu bar rendering

    private func refresh() {
        guard let button = statusItem.button else { return }
        let presentation = MenuBarPresentation.make(
            phase: engine.phase, remainingSeconds: engine.remainingSeconds,
            format: preferences.menuBarTimeFormat, showTime: preferences.menuBarShowTime,
            emergencySeconds: emergency.isActive ? emergency.remainingSeconds : nil
        )
        button.image = presentation.symbol.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: "Timer")
        }
        if presentation.title.isEmpty {
            button.attributedTitle = NSAttributedString(string: "")
        } else {
            let prefix = presentation.symbol == nil ? "" : " "
            button.attributedTitle = NSAttributedString(
                string: prefix + presentation.title,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)]
            )
        }
    }
}
