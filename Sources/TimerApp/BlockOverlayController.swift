import AppKit
import SwiftUI
import TimerCore

/// v16 centered block popup (replaces the v3–v15 top-center toast): a small
/// non-activating, click-through HUD explaining the intervention — shield
/// icon, "Fokus läuft · noch <remaining>", and which target waits until the
/// session ends. One wording for both block modes. Auto-hides after 2.5 s;
/// each target is announced at most once per 10 s.
final class BlockOverlayController {
    private static let size = NSSize(width: 300, height: 90)
    private let panel: NSPanel
    private var hideTimer: Foundation.Timer?
    private var lastShown: [String: Date] = [:]

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
    }

    /// Shows the centered popup for a blocked target (app name or domain),
    /// with the session's remaining seconds at this moment, unless the same
    /// target was announced within the last 10 s.
    func show(target name: String, remainingSeconds: Int) {
        let nowDate = Date()
        if let last = lastShown[name], nowDate.timeIntervalSince(last) < 10 { return }
        lastShown[name] = nowDate

        let view = BlockPopupView(
            remaining: TimeFormatting.format(seconds: remainingSeconds),
            targetName: name
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: area.midX - panel.frame.width / 2,
                y: area.midY - panel.frame.height / 2
            ))
        }
        panel.orderFrontRegardless()

        hideTimer?.invalidate()
        hideTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.panel.orderOut(nil)
        }
    }
}

/// The popup content — same HUD styling family as the floating display.
private struct BlockPopupView: View {
    let remaining: String
    let targetName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Fokus läuft · noch \(remaining)")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                Text("\(targetName) wartet bis zum Ende")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(width: 300, height: 90, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, .dark)
    }
}
