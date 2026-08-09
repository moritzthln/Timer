import AppKit
import CoreGraphics
import SwiftUI
import TimerCore

/// The last rungs of the escalation ladder — v18 introduced this as a cover
/// for apps that can be neither hidden nor pulled out of fullscreen, v21
/// turned it from decoration into the mechanism that actually works, and v22
/// reuses the very same window for blocked *websites*.
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
///
/// **Two modes, one window (v22).** The app cover fills the screen and may
/// take activation; the site cover is shown at an explicit frame — the
/// browser's content area — and never activates, because escaping a blocked
/// tab needs the tab bar and the tab bar needs the browser in front. `mode`
/// keeps them apart: the app cover always wins (it is the stronger
/// intervention and its Space escape must not be undercut), and every
/// teardown but the full one is scoped to its own mode.
final class BlockCoverController {
    /// What the window is showing right now.
    private enum Mode: Equatable {
        case none
        /// v18/v21: a blocked app, full screen.
        case app(bundleID: String?)
        /// v22: a blocked website, over its browser's content area.
        case site(host: String)
    }

    private let window: BlockCoverWindow
    private var hosting: NSHostingView<BlockCoverView>?
    private var mode: Mode = .none
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

    var isShowing: Bool { mode != .none }

    /// Whether an app cover owns the window — the site path stands back then.
    var isShowingApp: Bool {
        if case .app = mode { return true }
        return false
    }

    /// The app currently covered; nil unless an app cover is up.
    var coveredBundleID: String? {
        if case .app(let bundleID) = mode { return bundleID }
        return nil
    }

    /// Covers the active screen for the given app. Re-showing the same app
    /// only refreshes the countdown (no flicker, no re-ordering), so the
    /// 2 s re-enforcement poll keeps the remaining time current. A site cover
    /// is simply taken over: the app intervention outranks it.
    func show(target name: String, bundleID: String?, remainingSeconds: Int, escaped: Bool) {
        let sameApp = mode == .app(bundleID: bundleID)
        self.escaped = escaped || (sameApp && self.escaped)
        render(
            BlockCoverView(
                headline: headline(remainingSeconds: remainingSeconds),
                targetName: name,
                note: self.escaped ? "Vollbild beendet — zurück zum Fokus." : nil,
                hint: "⌘ Tab wechselt weg — dann verschwindet der Hinweis.",
                compact: false
            ),
            reuseHosting: sameApp
        )
        mode = .app(bundleID: bundleID)
        if let screen = NSScreen.main {
            window.setFrame(screen.frame, display: true)
        }
        window.orderFrontRegardless()
    }

    /// v22 site cover: the same window over one browser's content area, so the
    /// tab bar (and Arc's sidebar) stay clickable — the cover is meant to be
    /// escapable, only staying costs the tab switch.
    ///
    /// Deliberately no `NSApp.activate` and no key window: the browser has to
    /// stay frontmost for its own chrome to be usable. Returns false when an
    /// app cover owns the window, so the caller knows no cover went up.
    @discardableResult
    func showSite(host: String, frame: NSRect, remainingSeconds: Int) -> Bool {
        guard !isShowingApp else { return false }
        let sameHost = mode == .site(host: host)
        escaped = false
        render(
            BlockCoverView(
                headline: headline(remainingSeconds: remainingSeconds),
                targetName: host,
                note: nil,
                hint: "Tab wechseln oder warten — in 10 s wechselt der Timer selbst.",
                compact: true
            ),
            reuseHosting: sameHost
        )
        mode = .site(host: host)
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        return true
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

    /// Takes the cover down whatever it shows — on deactivation, session end,
    /// pause, shield off, and app quit.
    func hide() {
        guard isShowing else { return }
        mode = .none
        escaped = false
        window.orderOut(nil)
    }

    /// Mode-scoped teardown: an app cover only. The 2 s poll calls this
    /// whenever something harmless is in front, which is exactly the situation
    /// a site cover lives in — it must survive that.
    func hideApp() {
        guard isShowingApp else { return }
        hide()
    }

    /// Targeted teardown: only takes down a cover belonging to this app.
    func hide(ifCovering bundleID: String?) {
        guard mode == .app(bundleID: bundleID) else { return }
        hide()
    }

    /// Mode-scoped teardown: a site cover only — the app ladder's cover stays.
    func hideSite() {
        guard case .site = mode else { return }
        hide()
    }

    /// Swaps the content, reusing the hosting view when the target did not
    /// change so a refresh neither flickers nor re-orders the window.
    private func render(_ view: BlockCoverView, reuseHosting: Bool) {
        if let hosting, reuseHosting {
            hosting.rootView = view
        } else {
            let created = NSHostingView(rootView: view)
            window.contentView = created
            hosting = created
        }
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

/// The cover content — the popup's wording, blown up to cover size. `compact`
/// is the v22 site variant: the same layout at browser-window scale, since a
/// content area can be a quarter of the screen.
private struct BlockCoverView: View {
    let headline: String
    let targetName: String
    /// Optional second line explaining an intervention the user did not ask
    /// for (v21: the fullscreen Space that was left).
    let note: String?
    /// The way out, in one line.
    let hint: String
    let compact: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
            VStack(spacing: compact ? 10 : 14) {
                Image(systemName: "shield.fill")
                    .font(.system(size: compact ? 30 : 44, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(headline)
                    .font(.system(size: compact ? 22 : 30, weight: .semibold))
                    .monospacedDigit()
                Text("\(targetName) wartet bis zum Ende")
                    .font(.system(size: compact ? 15 : 17))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let note {
                    Text(note)
                        .font(.system(size: compact ? 13 : 15))
                        .foregroundStyle(.secondary)
                }
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(compact ? 24 : 40)
        }
        // Claims every click so the app underneath stays untouchable.
        .contentShape(Rectangle())
        .environment(\.colorScheme, .dark)
    }
}
