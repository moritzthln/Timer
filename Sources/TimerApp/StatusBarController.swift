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
    private let statsWindow: StatsWindowController
    private let hotkeys = HotkeyManager()
    private let activityStore = ActivityStore(directory: ActivityStore.defaultDirectory())
    private var activityTracker: ActivityTrackerController?
    private var cancellable: AnyCancellable?
    private var midnightTimer: Foundation.Timer?

    init(engine: TimerEngine, preferences: Preferences) {
        self.engine = engine
        self.preferences = preferences
        floatingController = FloatingPanelController(engine: engine, preferences: preferences)
        settingsController = SettingsWindowController(preferences: preferences)
        focusBlock = FocusBlockController(preferences: preferences, overlay: overlay)
        statsWindow = StatsWindowController(stats: stats, activity: activityStore)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        activityTracker = ActivityTrackerController(store: activityStore, preferences: preferences)

        wireEngineCallbacks()
        wireHotkeys()
        configurePopover()
        configureStatusItem()
        observeSettingsChanges()
        scheduleMidnightRefresh()
        refresh()
    }

    // MARK: - Setup

    private func wireEngineCallbacks() {
        engine.onFocusSegmentEnded = { [weak self] segment in
            self?.stats.add(focusFrom: segment.start, to: segment.end)
        }

        cancellable = engine.objectWillChange.sink { [weak self] _ in
            // objectWillChange fires before mutation; refresh after it lands.
            DispatchQueue.main.async {
                guard let self else { return }
                self.refresh()
                self.focusBlock.update(phase: self.engine.phase)
            }
        }

        engine.onFinish = { [weak self] in
            guard let self else { return }
            self.showPopover()
            if self.preferences.soundEnabled {
                SoundPlayer.playCompletionChime(volume: self.preferences.alarmVolume)
            }
        }

        engine.onPhaseChange = { [weak self] _ in
            guard let self else { return }
            self.showPopover()
            if self.preferences.soundEnabled {
                SoundPlayer.playCompletionChime(volume: self.preferences.alarmVolume)
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
            }
        }
        hotkeys.apply(
            popover: preferences.hotkeyPopover,
            quickStart: preferences.hotkeyQuickStart
        )
    }

    private func configurePopover() {
        popover.contentViewController = NSHostingController(
            rootView: TimerView(
                engine: engine, preferences: preferences, stats: stats,
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
                quickStart: self?.preferences.hotkeyQuickStart ?? nil
            )
            self?.refresh()
        }
    }

    // MARK: - Activity tracking

    /// Called from applicationWillTerminate: closes open activity segments.
    func flushActivity() {
        activityTracker?.flush()
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
        if case .idle = engine.phase {
            button.image = MenuBarRingRenderer.image(progress: todayGoalProgress())
            button.attributedTitle = NSAttributedString(string: "")
            return
        }
        let presentation = MenuBarPresentation.make(
            phase: engine.phase, remainingSeconds: engine.remainingSeconds
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

    /// Today's focus vs. the daily goal, uncapped (the renderer clamps).
    private func todayGoalProgress() -> Double {
        let goalSeconds = Double(preferences.dailyGoalMinutes) * 60
        guard goalSeconds > 0 else { return 0 }
        return stats.todaySeconds() / goalSeconds
    }

    /// Re-renders the idle ring right after local midnight (day rollover),
    /// then re-arms for the next day.
    private func scheduleMidnightRefresh() {
        midnightTimer?.invalidate()
        let calendar = GoalRules.localISOCalendar()
        let startOfToday = calendar.startOfDay(for: Date())
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return }
        let timer = Foundation.Timer(
            fire: nextMidnight.addingTimeInterval(1), interval: 0, repeats: false
        ) { [weak self] _ in
            self?.refresh()
            self?.scheduleMidnightRefresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }
}
