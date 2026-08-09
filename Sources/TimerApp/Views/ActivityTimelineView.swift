import SwiftUI
import TimerCore

/// v9: zoomable, pannable day timeline with adaptive tick labels and
/// per-segment tooltips. Zoom is per-window-session state: the parent tags
/// this view with `.id(day)` (reset on date change) and the stats window
/// rebuilds its view tree on every open (reset on reopen). Only this strip
/// scrolls horizontally — the rest of the tab never does. v11: the zoom
/// and pan mechanics live in the shared `TimelineZoomContainer` (also used
/// by the week view); this file keeps only the day content. v19: the rects
/// themselves come from the shared `TimelineSegmentsView`, which also draws
/// the highlight layer of a selected promoted website row.
struct ActivityTimelineView: View {
    let first: Date
    let last: Date
    let summary: DaySummary
    let colorFor: (String) -> Color
    /// v10 drill-down: with a selection, other apps' segments dim to 0.15.
    /// v19: a promoted website row matches no app, so all of them dim and
    /// that domain's site spans are drawn on top instead.
    let selectedBundleID: String?
    /// v19: the configured promoted domains — the ownership rule behind the
    /// highlighted spans (first matching entry wins, as in the row totals).
    let promotedSites: [String]
    /// v10: focus sessions drawn as an accent trace under the bar, on the
    /// same axis (so it zooms and pans with the bar). v11: additionally
    /// overlaid on the bar itself as a wash + edge lines (`FocusBarOverlay`).
    let focusIntervals: [FocusInterval]
    /// v12: with the filter on, segments outside focus intervals dim to
    /// ~0.15 (`FocusDimMask`), multiplying with the drill-down dimming.
    let focusOnly: Bool

    private static let barHeight: CGFloat = 32
    private static let labelHeight: CGFloat = 12
    private static let traceHeight: CGFloat = 5
    private static let rowSpacing: CGFloat = 3
    /// Fixed total height: controls + bar + focus trace + tick labels +
    /// three gaps (the trace strip is always reserved, even when empty).
    static let totalHeight: CGFloat =
        TimelineZoom.controlsHeight + barHeight + traceHeight + labelHeight + 3 * rowSpacing

    private static var hourFormatter: DateFormatter { TimelineClock.hour }

    private var span: TimeInterval { last.timeIntervalSince(first) }

    /// The selected promoted row's domain (nil while an app — or nothing —
    /// is selected).
    private var selectedDomain: String? {
        selectedBundleID.flatMap(SitePromotion.domain(forRowID:))
    }

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
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.6))
            segmentLayer(width: width)
            highlightLayer(width: width)
            FocusBarOverlay(fractions: focusFractions, width: width)
        }
        .frame(width: width, height: Self.barHeight)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// The app segments as one layer, so the v12 focus mask can dim the
    /// regions outside focus intervals without touching the track
    /// background, the wash or the edge lines.
    private func segmentLayer(width: CGFloat) -> some View {
        TimelineSegmentsView(
            spans: TimelineSpan.apps(
                summary, origin: first, selectedID: selectedBundleID,
                colorFor: colorFor, tooltips: true
            ),
            axisSpan: span, width: width, height: Self.barHeight
        )
        .mask(alignment: .leading) { dimMask(width: width) }
    }

    /// v19: with a promoted website row selected, that domain's site spans sit
    /// on top of the dimmed app segments at full opacity. The focus filter
    /// clips them in the data, so this layer needs no dim mask; the wash and
    /// the edge lines still go over it.
    @ViewBuilder
    private func highlightLayer(width: CGFloat) -> some View {
        if let domain = selectedDomain, let selectedBundleID {
            TimelineSegmentsView(
                spans: TimelineSpan.promotedSites(
                    summary, origin: first, domain: domain, promoted: promotedSites,
                    clip: focusOnly ? focusIntervals : nil,
                    color: colorFor(selectedBundleID), tooltips: true
                ),
                axisSpan: span, width: width, height: Self.barHeight
            )
        }
    }

    @ViewBuilder
    private func dimMask(width: CGFloat) -> some View {
        if focusOnly {
            FocusDimMask(fractions: focusFractions, width: width)
        } else {
            Rectangle()
        }
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
