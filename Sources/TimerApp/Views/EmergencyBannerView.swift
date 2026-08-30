import SwiftUI
import TimerCore

/// v24: what the popover shows while an emergency session runs — the
/// remaining time and the one way out. The timer and pomodoro controls stay
/// underneath: a focus session may run alongside, both simply coexist.
struct EmergencyBannerView: View {
    @ObservedObject var emergency: EmergencyController

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                Text(tr("Notfall-Modus · noch \(TimeFormatting.format(seconds: emergency.remainingSeconds))", "Emergency mode · \(TimeFormatting.format(seconds: emergency.remainingSeconds)) left"))
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
            }
            HoldToCancelButton(action: emergency.cancel)
        }
        .foregroundStyle(Color.orange)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.14))
        )
    }
}

/// The single cancel path of the emergency mode: hold for ten seconds while
/// the ring fills. Releasing early resets it to zero — deliberately no
/// keyboard shortcut and no menu item, because a mode you can leave in one
/// click is not the mode this is meant to be.
struct HoldToCancelButton: View {
    /// Spec: ten seconds, and the ring has to show it.
    var holdSeconds: Double = 10
    let action: () -> Void

    /// Fine enough for a smooth ring, coarse enough to stay cheap.
    private static let interval = 0.05

    @State private var progress: Double = 0
    @State private var ticker: Foundation.Timer?

    var body: some View {
        HStack(spacing: 6) {
            ring
            Text(label)
                .font(.system(size: 11))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.orange.opacity(progress > 0 ? 0.22 : 0.12))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        // A zero-distance drag is the press-and-hold: onChanged marks the
        // press, onEnded the release. A plain Button would fire on click.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginHold() }
                .onEnded { _ in reset() }
        )
        .onDisappear(perform: reset)
        .help(tr("Notfall-Modus beenden — Knopf \(Int(holdSeconds)) Sekunden gedrückt halten.", "End the emergency mode — hold the button for \(Int(holdSeconds)) seconds."))
    }

    private var label: String {
        guard progress > 0 else { return tr("Abbrechen · \(Int(holdSeconds)) s halten", "Cancel · hold \(Int(holdSeconds)) s") }
        let left = Int(((1 - progress) * holdSeconds).rounded(.up))
        return tr("Halten … \(left) s", "Holding … \(left) s")
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.orange.opacity(0.3), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 13, height: 13)
    }

    /// `onChanged` repeats for the whole press, so starting has to be
    /// idempotent — the running ticker is the "already holding" flag.
    private func beginHold() {
        guard ticker == nil else { return }
        let timer = Foundation.Timer.scheduledTimer(
            withTimeInterval: Self.interval, repeats: true
        ) { _ in
            tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        progress = min(1, progress + Self.interval / holdSeconds)
        guard progress >= 1 else { return }
        reset()
        action()
    }

    private func reset() {
        ticker?.invalidate()
        ticker = nil
        progress = 0
    }
}
