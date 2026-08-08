import SwiftUI
import TimerCore

/// v9: zoomable, pannable day timeline with adaptive tick labels and
/// per-segment tooltips. Zoom is per-window-session state: the parent tags
/// this view with `.id(day)` (reset on date change) and the stats window
/// rebuilds its view tree on every open (reset on reopen). Only this strip
/// scrolls horizontally — the rest of the tab never does. v11: the zoom
/// and pan mechanics live in the shared `TimelineZoomContainer` (also used
/// by the week view); this file keeps only the day content.
struct ActivityTimelineView: View {
    let first: Date
    let last: Date
    let summary: DaySummary
    let colorFor: (String) -> Color
    /// v10 drill-down: with a selection, other apps' segments dim to 0.15.
    let selectedBundleID: String?
    /// v10: focus sessions drawn as an accent trace under the bar, on the
    /// same axis (so it zooms and pans with the bar). v11: additionally
    /// overlaid on the bar itself as a wash + edge lines (`FocusBarOverlay`).
    let focusIntervals: [FocusInterval]

    private static let barHeight: CGFloat = 32
    private static let labelHeight: CGFloat = 12
    private static let traceHeight: CGFloat = 5
    private static let rowSpacing: CGFloat = 3
    /// Fixed total height: controls + bar + focus trace + tick labels +
    /// three gaps (the trace strip is always reserved, even when empty).
    static let totalHeight: CGFloat =
        TimelineZoom.controlsHeight + barHeight + traceHeight + labelHeight + 3 * rowSpacing

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    private var span: TimeInterval { last.timeIntervalSince(first) }

    var body: some View {
        TimelineZoomContainer(spacing: Self.rowSpacing) { width, viewportWidth in
            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                bar(width: width)
                focusTraces(width: width)
                tickLabels(width: width, viewportWidth: viewportWidth)
            }
        }
        .frame(height: Self.totalHeight)
    }

    // MARK: - Bar and focus marks

    private func bar(width: CGFloat) -> some View {
        let allSegments = summary.apps.flatMap(\.segments)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.6))
            ForEach(allSegments) { segment in
                if case .app(let bundleID, let name) = segment.kind {
                    let x = segment.start.timeIntervalSince(first) / span
                    let w = segment.end.timeIntervalSince(segment.start) / span
                    Rectangle()
                        .fill(colorFor(bundleID))
                        .opacity(dimOpacity(for: bundleID))
                        .frame(width: max(1, width * w))
                        .offset(x: width * x)
                        .help(Self.tooltip(name: name, segment: segment))
                }
            }
            FocusBarOverlay(fractions: focusFractions, width: width)
        }
        .frame(width: width, height: Self.barHeight)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// v11: the focus intervals as clamped fractions of the presence axis —
    /// drawn as the wash overlay on the bar and as the under-bar traces.
    private var focusFractions: [(start: CGFloat, end: CGFloat)] {
        focusIntervals.compactMap { interval in
            FocusBarOverlay.clampedFractions(
                startOffset: interval.start.timeIntervalSince(first),
                endOffset: interval.end.timeIntervalSince(first),
                span: span
            )
        }
    }

    private func dimOpacity(for bundleID: String) -> Double {
        guard let selectedBundleID else { return 1 }
        return selectedBundleID == bundleID ? 1 : 0.15
    }

    /// 5 pt rounded accent marks under the bar where focus sessions ran
    /// (v11: grown from 2 pt), clamped to the presence axis. The strip is
    /// always laid out so the total height (and the window minimum derived
    /// from it) never changes. The focus tooltip lives here, not on the wash.
    private func focusTraces(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(focusIntervals.indices, id: \.self) { index in
                let interval = focusIntervals[index]
                if let fraction = FocusBarOverlay.clampedFractions(
                    startOffset: interval.start.timeIntervalSince(first),
                    endOffset: interval.end.timeIntervalSince(first),
                    span: span
                ) {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(Self.traceHeight, width * (fraction.end - fraction.start)))
                        .offset(x: width * fraction.start)
                        .help(Self.focusTooltip(interval))
                }
            }
        }
        .frame(width: width, height: Self.traceHeight, alignment: .leading)
    }

    /// "Fokus · 14:02–14:31" (the interval's real times, even when the
    /// drawn mark is clamped to the axis).
    static func focusTooltip(_ interval: FocusInterval) -> String {
        "Fokus · \(hourFormatter.string(from: interval.start))–\(hourFormatter.string(from: interval.end))"
    }

    /// "Safari · 9:12–9:47 (35 min)". Presence gaps draw no segment rect,
    /// so they naturally get no tooltip.
    static func tooltip(name: String, segment: ActivitySegment) -> String {
        let start = hourFormatter.string(from: segment.start)
        let end = hourFormatter.string(from: segment.end)
        let duration = TimeFormatting.wording(
            seconds: segment.end.timeIntervalSince(segment.start)
        )
        return "\(name) · \(start)–\(end) (\(duration))"
    }

    // MARK: - Tick labels

    private func tickLabels(width: CGFloat, viewportWidth: CGFloat) -> some View {
        let interval = TimelineTicks.tickIntervalMinutes(
            zoom: width / max(viewportWidth, 1),
            spanMinutes: span / 60, viewportWidth: viewportWidth
        )
        return Group {
            if let interval {
                intervalTickLabels(width: width, intervalMinutes: interval)
            } else {
                coarseTickLabels()
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .frame(width: width, height: Self.labelHeight, alignment: .topLeading)
    }

    private func coarseTickLabels() -> some View {
        HStack {
            Text(Self.hourFormatter.string(from: first))
            Spacer()
            Text(Self.hourFormatter.string(from: first.addingTimeInterval(span / 2)))
            Spacer()
            Text(Self.hourFormatter.string(from: last))
        }
    }

    private func intervalTickLabels(width: CGFloat, intervalMinutes: Int) -> some View {
        let offsets = TimelineTicks.tickOffsetsMinutes(
            startMinuteOfDay: Self.minuteOfDay(of: first),
            spanMinutes: span / 60,
            intervalMinutes: intervalMinutes
        )
        return ZStack(alignment: .topLeading) {
            ForEach(offsets, id: \.self) { offset in
                Text(Self.hourFormatter.string(from: first.addingTimeInterval(offset * 60)))
                    .fixedSize()
                    .position(x: width * offset / (span / 60), y: Self.labelHeight / 2)
            }
        }
    }

    private static func minuteOfDay(of date: Date) -> Double {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return Double(comps.hour ?? 0) * 60 + Double(comps.minute ?? 0)
            + Double(comps.second ?? 0) / 60
    }
}
