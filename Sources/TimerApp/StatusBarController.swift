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
    private var cancellable: AnyCancellable?

    init(engine: TimerEngine, preferences: Preferences) {
        self.engine = engine
        self.preferences = preferences
        floatingController = FloatingPanelController(engine: engine, preferences: preferences)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover.contentViewController = NSHostingController(
            rootView: TimerView(
                engine: engine, preferences: preferences,
                onOpenSettings: { [weak self] in self?.openSettings() },
                onToggleFloating: { [weak self] in self?.toggleFloating() }
            )
        )
        popover.behavior = .transient

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

        cancellable = engine.objectWillChange.sink { [weak self] _ in
            // objectWillChange fires before mutation; refresh after it lands.
            DispatchQueue.main.async { self?.refresh() }
        }

        engine.onFinish = { [weak self] in
            guard let self else { return }
            self.showPopover()
            if preferences.soundEnabled {
                SoundPlayer.playCompletionChime(volume: preferences.alarmVolume)
            }
        }

        engine.onPhaseChange = { [weak self] _ in
            guard let self else { return }
            self.showPopover()
            if preferences.soundEnabled {
                SoundPlayer.playCompletionChime(volume: preferences.alarmVolume)
            }
        }

        refresh()
    }

    // MARK: - Windows (filled in Tasks 7/8)

    private func openSettings() {
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
}
