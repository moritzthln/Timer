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
    private let overlay = BlockOverlayController()
    private let focusBlock: FocusBlockController
    private let focusMode: FocusModeController
    private let statsWindow: StatsWindowController
    private let hotkeys = HotkeyManager()
    private let activityStore = ActivityStore(directory: ActivityStore.defaultDirectory())
    private let focusLog = FocusLog(directory: FocusLog.defaultDirectory())
    private var activityTracker: ActivityTrackerController?
    private var cancellable: AnyCancellable?

    init(engine: TimerEngine, preferences: Preferences) {
        self.engine = engine
        self.preferences = preferences
        floatingController = FloatingPanelController(engine: engine, preferences: preferences)
        focusMode = FocusModeController(preferences: preferences)
        settingsController = SettingsWindowController(preferences: preferences, focusMode: focusMode)
        focusBlock = FocusBlockController(preferences: preferences, overlay: overlay)
        statsWindow = StatsWindowController(
            stats: stats, activity: activityStore, focusLog: focusLog,
            liveFocusStart: { [weak engine] in engine?.activeFocusStart },
            // v13: read live so settings edits reach the next render/reopen.
            promotedSites: { preferences.promotedSites }
        )
        activityTracker = ActivityTrackerController(store: activityStore, preferences: preferences)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        wireEngineCallbacks()
        wireHotkeys()
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
            }
        }
        hotkeys.apply(
            popover: preferences.hotkeyPopover,
            quickStart: preferences.hotkeyQuickStart,
            extend: preferences.hotkeyExtend
        )
    }

    private func configurePopover() {
        popover.contentViewController = NSHostingController(
            rootView: TimerView(
                engine: engine, preferences: preferences,
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
                keyEquivalent: "q"
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
                extend: self?.preferences.hotkeyExtend ?? nil
            )
            self?.refresh()
        }
    }

    // MARK: - Activity tracking

    /// Final activity flush + best-effort Focus-mode off on quit; v16 also
    /// unhides everything the focus block hid, so nothing stays invisible
    /// after the Timer is gone.
    func prepareForTermination() {
        activityTracker?.flush()
        focusMode.deactivateForTermination()
        focusBlock.restoreHiddenApps()
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
        // Accessory apps must activate, otherwise the text field gets no focus.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    // MARK: - Menu bar rendering

    private func refresh() {
        guard let button = statusItem.button else { return }
        let presentation = MenuBarPresentation.make(
            phase: engine.phase, remainingSeconds: engine.remainingSeconds,
            format: preferences.menuBarTimeFormat, showTime: preferences.menuBarShowTime
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
