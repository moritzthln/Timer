import AppKit
import CoreGraphics
import SwiftUI
import TimerCore

/// The last rungs of the escalation ladder — v18 introduced this as a cover
/// for apps that can be neither hidden nor pulled out of fullscreen, v21
/// turned it from decoration into the mechanism that actually works.
///
/// The v18 panel only ever called `orderFrontRegardless()` from an accessory
/// app that never activates, and macOS keeps another app's fullscreen Space
/// exclusive: the cover was drawn into a Space nobody could see, which is why
/// fullscreen apps were unblockable. It is now a borderless `NSWindow` that
/// **can become key**, sitting at `CGShieldingWindowLevel()` (the level the
/// screen-lock utilities use — above fullscreen windows and the menu bar), so
/// `escape()` can activate the Timer and give macOS a reason to switch the
/// Space away from the blocked app.
///
/// It swallows clicks — the app underneath has to be unusable, otherwise the
/// cover would be decoration again — but never the keyboard, so ⌘Tab still
/// leaves; the cover comes down as soon as the covered app is hidden or no
/// longer frontmost.
final class BlockCoverController {
    private let window: BlockCoverWindow
    private var hosting: NSHostingView<BlockCoverView>?
    /// The app currently covered; nil while no cover is up.
    private(set) var coveredBundleID: String?
    /// Whether this cover came up as part of a Space escape. It stays set for
    /// the life of the cover, so a later ladder rung refreshing the same app
    /// does not drop the explanation for the jump the user did not ask for.
    private var escaped = false

    init() {
        window = BlockCoverWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        window.isMovable = false
        window.isRestorable = false
    }

    var isShowing: Bool { coveredBundleID != nil }

    /// Covers the active screen for the given app. Re-showing the same app
    /// only refreshes the countdown (no flicker, no re-ordering), so the
    /// 2 s re-enforcement poll keeps the remaining time current.
    func show(target name: String, bundleID: String?, remainingSeconds: Int, escaped: Bool) {
        let sameApp = isShowing && coveredBundleID == bundleID
        self.escaped = escaped || (sameApp && self.escaped)
        let view = BlockCoverView(
            headline: headline(remainingSeconds: remainingSeconds),
            targetName: name,
            escaped: self.escaped
        )
        if let hosting, sameApp {
            hosting.rootView = view
        } else {
            let created = NSHostingView(rootView: view)
            window.contentView = created
            hosting = created
        }
        coveredBundleID = bundleID
        if let screen = NSScreen.main {
            window.setFrame(screen.frame, display: true)
        }
        window.orderFrontRegardless()
    }

    /// v21 rung 3 — the Space escape itself. The Timer is an accessory
    /// (LSUIElement) app, and that does *not* prevent key windows: the
    /// popover's auto-focused minute field has relied on activate + key since
    /// v6. So no activation-policy flip is needed here — an `.accessory` app
    /// that activates with a key-capable window is enough for macOS to leave
    /// the blocked app's fullscreen Space. Flipping to `.regular` would buy
    /// nothing and cost a Dock icon plus a menu bar takeover mid-block.
    ///
    /// Call order matters: the cover is already on screen (on the Timer's own
    /// Space) when the activation lands, so there is something to switch to.
    func escape() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Takes the cover down — on deactivation, session end, pause, shield
    /// off, app quit, and whenever the covered app stops being frontmost.
    func hide() {
        guard isShowing else { return }
        coveredBundleID = nil
        escaped = false
        window.orderOut(nil)
    }

    /// Targeted teardown: only takes down a cover belonging to this app.
    func hide(ifCovering bundleID: String?) {
        guard isShowing, coveredBundleID == bundleID else { return }
        hide()
    }

    /// The countdown is the point of the cover during a session. The v21
    /// diagnostic runs the same ladder without one, so it gets the neutral
    /// wording instead of a "Fokus läuft · noch 0:00" that is simply untrue.
    private func headline(remainingSeconds: Int) -> String {
        guard remainingSeconds > 0 else { return "Fokus-Block" }
        return "Fokus läuft · noch \(TimeFormatting.format(seconds: remainingSeconds))"
    }
}

/// The one thing the v18 panel could not do: become key. Borderless windows
/// refuse by default, and `.nonactivatingPanel` refused twice over — without
/// a key window `NSApp.activate` has nothing to switch the Space to.
private final class BlockCoverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The cover content — the popup's wording, blown up to screen size.
private struct BlockCoverView: View {
    let headline: String
    let targetName: String
    /// v21: the cover pulled the user out of a fullscreen Space, so it also
    /// explains the jump.
    let escaped: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
            VStack(spacing: 14) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(headline)
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
                Text("\(targetName) wartet bis zum Ende")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if escaped {
                    Text("Vollbild beendet — zurück zum Fokus.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                Text("⌘ Tab wechselt weg — dann verschwindet der Hinweis.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
            .padding(40)
        }
        // Claims every click so the app underneath stays untouchable.
        .contentShape(Rectangle())
        .environment(\.colorScheme, .dark)
    }
}
