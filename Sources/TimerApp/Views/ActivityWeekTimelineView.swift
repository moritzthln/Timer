import SwiftUI
import TimerCore

/// v10: seven aligned slim day rows (Mon top ... Sun bottom) sharing one
/// time-of-day axis — from the earliest first-activity to the latest
/// last-activity across the week — with coarse hour ticks under the bottom
/// row only. No zoom here; clicking a row jumps to that day's day view.
struct ActivityWeekTimelineView: View {
    let days: [WeekDay]
    let colorFor: (String) -> Color
    /// v10 drill-down: with a selection, other apps' segments dim to 0.15.
    let selectedBundleID: String?
    let onOpenDay: (Date) -> Void

    static let rowHeight: CGFloat = 16
    static let rowSpacing: CGFloat = 4
    static let labelWidth: CGFloat = 36
    static let labelGap: CGFloat = 8
    static let ticksHeight: CGFloat = 12
    /// Seven rows, six gaps between them, one gap above the tick labels.
    static var minHeight: CGFloat {
        7 * rowHeight + 7 * rowSpacing + ticksHeight
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "ccc d."
        return formatter
    }()

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    /// Shared axis as seconds since local midnight, or nil for an all-empty
    /// week (rows then render as blank tracks without ticks).
    private var axis: (start: TimeInterval, span: TimeInterval)? {
        var earliest: TimeInterval?
        var latest: TimeInterval?
        for day in days {
            let dayStart = Calendar.current.startOfDay(for: day.date)
            if let first = day.summary.firstActivity {
                let offset = first.timeIntervalSince(dayStart)
                earliest = min(earliest ?? offset, offset)
            }
            if let last = day.summary.lastActivity {
                let offset = last.timeIntervalSince(dayStart)
                latest = max(latest ?? offset, offset)
            }
        }
        guard let earliest, let latest, latest > earliest else { return nil }
        return (earliest, latest - earliest)
    }

    var body: some View {
        let axis = self.axis
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(days) { day in
                row(day, axis: axis)
            }
            if axis != nil {
                tickLabels(axis: axis!)
            } else {
                Spacer().frame(height: Self.ticksHeight)
            }
        }
    }

    // MARK: - Rows

    private func row(_ day: WeekDay, axis: (start: TimeInterval, span: TimeInterval)?) -> some View {
        HStack(spacing: Self.labelGap) {
            Text(Self.dayFormatter.string(from: day.date))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: Self.labelWidth, alignment: .leading)
            track(day, axis: axis)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpenDay(day.date) }
    }

    private func track(_ day: WeekDay, axis: (start: TimeInterval, span: TimeInterval)?) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary.opacity(0.6))
                if let axis {
                    segments(day, axis: axis, width: geo.size.width)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: Self.rowHeight)
    }

    private func segments(
        _ day: WeekDay, axis: (start: TimeInterval, span: TimeInterval), width: CGFloat
    ) -> some View {
        let dayStart = Calendar.current.startOfDay(for: day.date)
        let allSegments = day.summary.apps.flatMap(\.segments)
        return ForEach(allSegments) { segment in
            if case .app(let bundleID, _) = segment.kind {
                let x = (segment.start.timeIntervalSince(dayStart) - axis.start) / axis.span
                let w = segment.end.timeIntervalSince(segment.start) / axis.span
                Rectangle()
                    .fill(colorFor(bundleID))
                    .opacity(dimOpacity(for: bundleID))
                    .frame(width: max(1, width * w))
                    .offset(x: width * x)
            }
        }
    }

    private func dimOpacity(for bundleID: String) -> Double {
        guard let selectedBundleID else { return 1 }
        return selectedBundleID == bundleID ? 1 : 0.15
    }

    // MARK: - Ticks

    /// Coarse start/mid/end labels (the week view has no zoom), indented to
    /// start under the tracks.
    private func tickLabels(axis: (start: TimeInterval, span: TimeInterval)) -> some View {
        let dayStart = Calendar.current.startOfDay(for: days.first?.date ?? Date())
        let start = dayStart.addingTimeInterval(axis.start)
        return HStack {
            Text(Self.hourFormatter.string(from: start))
            Spacer()
            Text(Self.hourFormatter.string(from: start.addingTimeInterval(axis.span / 2)))
            Spacer()
            Text(Self.hourFormatter.string(from: start.addingTimeInterval(axis.span)))
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .frame(height: Self.ticksHeight)
        .padding(.leading, Self.labelWidth + Self.labelGap)
    }
}
