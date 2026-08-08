import SwiftUI
import TimerCore

/// v10: a 7-bar mini chart in every app row — one bar per day, scaled to the
/// app's own 7-day maximum. Day view: the 7 days ending on the displayed day;
/// week view: the displayed week's seven days. Empty days are baseline stubs.
struct ActivitySparklineView: View {
    let values: [Double]
    let help: String

    static let size = CGSize(width: 44, height: 14)
    private static let stubHeight: CGFloat = 1.5

    var body: some View {
        let maxValue = values.max() ?? 0
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(values.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(.secondary.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .frame(height: barHeight(values[index], maxValue: maxValue))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .bottom)
        .help(help)
    }

    private func barHeight(_ value: Double, maxValue: Double) -> CGFloat {
        guard value > 0, maxValue > 0 else { return Self.stubHeight }
        return max(Self.stubHeight, Self.size.height * CGFloat(value / maxValue))
    }

    /// Per-app daily seconds across `summaries` (one entry per day, in
    /// order): the data behind the bars, keyed by bundle id. Apps missing
    /// on a day keep 0 for that slot.
    static func series(from summaries: [DaySummary]) -> [String: [Double]] {
        var result: [String: [Double]] = [:]
        for (index, summary) in summaries.enumerated() {
            for app in summary.apps {
                var values = result[app.bundleID] ?? Array(repeating: 0, count: summaries.count)
                values[index] = app.totalSeconds
                result[app.bundleID] = values
            }
        }
        return result
    }
}
