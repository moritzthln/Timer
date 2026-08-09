import AppKit
import SwiftUI
import TimerCore

/// v18 step 3 of the escalation ladder — the last resort for an app that can
/// be neither hidden nor pulled out of fullscreen (no Accessibility
/// permission, or a window that refuses): the screen it sits on is covered.
///
/// Sibling of the v16 popup, with two deliberate differences: this panel
/// lives at `.screenSaver` level (above fullscreen apps and the menu bar) and
/// it **swallows clicks** instead of being click-through — the app
/// underneath has to be unusable, otherwise the cover would be decoration.
/// It never blocks the keyboard, so ⌘Tab still leaves; the cover follows and
/// comes down as soon as the covered app is no longer frontmost.
final class BlockCoverController {
    private let panel: NSPanel
    private var hosting: NSHostingView<BlockCoverView>?
    /// The app currently covered; nil while no cover is up.
    private(set) var coveredBundleID: String?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
    }

    var isShowing: Bool { coveredBundleID != nil }

    /// Covers the active screen for the given app. Re-showing the same app
    /// only refreshes the countdown (no flicker, no re-ordering), so the
    /// 2 s re-enforcement poll keeps the remaining time current.
    func show(target name: String, bundleID: String?, remainingSeconds: Int) {
        let view = BlockCoverView(
            remaining: TimeFormatting.format(seconds: remainingSeconds),
            targetName: name
        )
        if let hosting, isShowing, coveredBundleID == bundleID {
            hosting.rootView = view
        } else {
            let created = NSHostingView(rootView: view)
            panel.contentView = created
            hosting = created
        }
        coveredBundleID = bundleID
        if let screen = NSScreen.main {
            panel.setFrame(screen.frame, display: true)
        }
        panel.orderFrontRegardless()
    }

    /// Takes the cover down — on deactivation, session end, pause, shield
    /// off, app quit, and whenever the covered app stops being frontmost.
    func hide() {
        guard isShowing else { return }
        coveredBundleID = nil
        panel.orderOut(nil)
    }

    /// Targeted teardown: only takes down a cover belonging to this app.
    func hide(ifCovering bundleID: String?) {
        guard isShowing, coveredBundleID == bundleID else { return }
        hide()
    }
}

/// The cover content — the popup's wording, blown up to screen size.
private struct BlockCoverView: View {
    let remaining: String
    let targetName: String

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
            VStack(spacing: 14) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Fokus läuft · noch \(remaining)")
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
                Text("\(targetName) wartet bis zum Ende")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
