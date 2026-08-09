import SwiftUI
import TimerCore

/// v10: seven aligned slim day rows (Mon top ... Sun bottom) sharing one
/// time-of-day axis — from the earliest first-activity to the latest
/// last-activity across the week. v11: the v9 zoom mechanic, lifted to the
/// week container — a fixed day-label column left and ONE shared horizontal
/// ScrollView right holding all seven tracks, the focus overlays, and the
/// bottom tick labels, so everything zooms and pans synchronously
/// (`TimelineZoomContainer`: −/＋/1× buttons, pinch at the pointer,
/// double-click ×2 on the clicked time). A single click on a row still
/// jumps to that day (arbitrated after the double-click via
/// `WeekRowHit` + `ExclusiveGesture`); clicking a day label jumps
/// immediately. The parent resets zoom per week via `.id(weekStart)`.
/// v20: every row's browser segments come in carved — promoted spans as
/// their own colored pieces, each row against its own day's data.
struct ActivityWeekTimelineView: View {
    let days: [WeekDay]
    let colorFor: (String) -> Color
    /// v10 drill-down: with a selection, other apps' segments dim to 0.15.
    /// v19: a promoted website row matches no app, so all of them dim and
    /// that domain's site spans are drawn on top — in every one of the seven
    /// rows, each against its own day's segments.
    let selectedBundleID: String?
    /// v19: the configured promoted domains — the ownership rule behind the
    /// highlighted spans (first matching entry wins, as in the row totals).
    let promotedSites: [String]
    /// v12: with the filter on, each row's segments outside that day's focus
    /// intervals dim to ~0.15 (`FocusDimMask`), multiplying with the
    /// drill-down dimming.
    let focusOnly: Bool
    let onOpenDay: (Date) -> Void

    static let rowHeight: CGFloat = 16
    static let traceHeight: CGFloat = 3
    static let traceGap: CGFloat = 1
    static let rowSpacing: CGFloat = 4
    static let labelWidth: CGFloat = 36
    static let labelGap: CGFloat = 8
    static let ticksHeight: CGFloat = 12
    /// Track plus the always-reserved focus trace strip below it.
    static var rowBlockHeight: CGFloat { rowHeight + traceGap + traceHeight }
    /// Controls row + seven row blocks + ticks + eight gaps (controls to
    /// rows, six between rows, one above the ticks). Zoomed-in overflow is
    /// handled by the scroll area, so the minimum never grows with zoom.
    static var minHeight: CGFloat {
        TimelineZoom.controlsHeight + 7 * rowBlockHeight + 8 * rowSpacing + ticksHeight
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "ccc d."
        return formatter
    }()

    private static var hourFormatter: DateFormatter { TimelineClock.hour }

    /// The selected promoted row's domain (nil while an app — or nothing —
    /// is selected).
    private var selectedDomain: String? {
        selectedBundleID.flatMap(SitePromotion.domain(forRowID:))
    }

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
        TimelineZoomContainer(
            spacing: Self.rowSpacing,
            leadingWidth: Self.labelWidth,
            leadingGap: Self.labelGap,
            onSingleClick: jumpToDay(at:),
            leading: { labelColumn },
            content: { width, viewportWidth in
                trackColumn(axis: axis, width: width, viewportWidth: viewportWidth)
            }
        )
        .frame(height: Self.minHeight)
    }

    /// Single click on the shared content: jump to the clicked row's day.
    /// Clicks in gaps or on the tick labels do nothing (the double-click
    /// zoom works there regardless).
    private func jumpToDay(at point: CGPoint) {
        guard let index = WeekRowHit.rowIndex(
            y: point.y, rowHeight: Self.rowBlockHeight,
            rowSpacing: Self.rowSpacing, rowCount: days.count
        ), days.indices.contains(index) else { return }
        onOpenDay(days[index].date)
    }

    // MARK: - Fixed label column

    /// Day labels never scroll; they stay put while the tracks zoom and
    /// pan. Clicking a label jumps to that day immediately.
    private var labelColumn: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(days) { day in
                Text(Self.dayFormatter.string(from: day.date))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(
                        width: Self.labelWidth, height: Self.rowBlockHeight,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenDay(day.date) }
            }
        }
    }

    // MARK: - Shared scroll content

    private func trackColumn(
        axis: (start: TimeInterval, span: TimeInterval)?, width: CGFloat, viewportWidth: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(days) { day in
                VStack(alignment: .leading, spacing: Self.traceGap) {
                    track(day, axis: axis, width: width)
                    focusTraces(day, axis: axis, width: width)
                }
            }
            if let axis {
                tickLabels(axis: axis, width: width, viewportWidth: viewportWidth)
            } else {
                Spacer().frame(height: Self.ticksHeight)
            }
        }
    }

    private func track(
        _ day: WeekDay, axis: (start: TimeInterval, span: TimeInterval)?, width: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(.quaternary.opacity(0.6))
            if let axis {
                segmentLayer(day, axis: axis, width: width)
                highlightLayer(day, axis: axis, width: width)
                FocusBarOverlay(fractions: focusFractions(day, axis: axis), width: width)
            }
        }
        .frame(width: width, height: Self.rowHeight)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    /// The row's app segments as one layer, so the v12 focus mask can dim
    /// the regions outside that day's focus intervals without touching the
    /// track background, the wash or the edge lines. v20: each row's browser
    /// segments arrive already carved by that day's promoted spans (its own
    /// focus intervals as the clip), so all seven rows mirror the list.
    private func segmentLayer(
        _ day: WeekDay, axis: (start: TimeInterval, span: TimeInterval), width: CGFloat
    ) -> some View {
        TimelineSegmentsView(
            spans: TimelineSpan.apps(
                day.summary, origin: origin(day, axis: axis), selectedID: selectedBundleID,
                colorFor: colorFor, tooltips: false,
                promoted: promotedSites, clip: focusOnly ? day.focus : nil
            ),
            axisSpan: axis.span, width: width, height: Self.rowHeight
        )
        .mask(alignment: .leading) { dimMask(day, axis: axis, width: width) }
    }

    /// v19: with a promoted website row selected, that day's spans of the
    /// domain sit on top of the app segments at full opacity — clipped to the
    /// day's focus intervals while the filter is on, and the only rects in the
    /// week rows carrying a tooltip (the carved v20 pieces stay tooltip-free
    /// here, as every week-row segment has since v10).
    @ViewBuilder
    private func highlightLayer(
        _ day: WeekDay, axis: (start: TimeInterval, span: TimeInterval), width: CGFloat
    ) -> some View {
        if let domain = selectedDomain, let selectedBundleID {
            TimelineSegmentsView(
                spans: TimelineSpan.promotedSites(
                    day.summary, origin: origin(day, axis: axis), domain: domain,
                    promoted: promotedSites, clip: focusOnly ? day.focus : nil,
                    color: colorFor(selectedBundleID), tooltips: true
                ),
                axisSpan: axis.span, width: width, height: Self.rowHeight
            )
        }
    }

    /// Wall-clock time the shared week axis starts at on `day`.
    private func origin(
        _ day: WeekDay, axis: (start: TimeInterval, span: TimeInterval)
    ) -> Date {
        Calendar.current.startOfDay(for: day.date).addingTimeInterval(axis.start)
    }

    @ViewBuilder
    private func dimMask(
        _ day: WeekDay, axis: (start: TimeInterval, span: TimeInterval), width: CGFloat
    ) -> some View {
        if focusOnly {
            FocusDimMask(fractions: focusFractions(day, axis: axis), width: width)
        } else {
            Rectangle()
        }
    }

    /// v11: the day's focus intervals as clamped fractions of the shared
    /// week axis — drawn as the wash overlay on the row and as the traces.
    private func focusFractions(
        _ day: WeekDay, axis: (start: TimeInterval, span: TimeInterval)
    ) -> [(start: CGFloat, end: CGFloat)] {
        let dayStart = Calendar.current.startOfDay(for: day.date)
        return day.focus.compactMap { interval in
            FocusBarOverlay.clampedFractions(
                startOffset: interval.start.timeIntervalSince(dayStart) - axis.start,
                endOffset: interval.end.timeIntervalSince(dayStart) - axis.start,
                span: axis.span
            )
        }
    }

    /// 3 pt rounded accent marks under each row where focus sessions ran
    /// (v11: grown from 2 pt) — same axis, no tooltips at this size (v10).
    /// The strip is always laid out so the rows keep their block height.
    private func focusTraces(
        _ day: WeekDay, axis: (start: TimeInterval, span: TimeInterval)?, width: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            if let axis {
                let fractions = focusFractions(day, axis: axis)
                ForEach(fractions.indices, id: \.self) { index in
                    let fraction = fractions[index]
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(
                            Self.traceHeight, width * (fraction.end - fraction.start)
                        ))
                        .offset(x: width * fraction.start)
                }
            }
        }
        .frame(width: width, height: Self.traceHeight, alignment: .leading)
    }

    // MARK: - Ticks

    /// v11: adaptive tick labels via the shared `TimelineTicks` math on the
    /// week axis — coarse start/mid/end at 1× (the v10 look), refining to
    /// hourly and quarter-hourly when zoomed in. They live inside the
    /// scroll content, so they pan and zoom with the rows.
    private func tickLabels(
        axis: (start: TimeInterval, span: TimeInterval), width: CGFloat, viewportWidth: CGFloat
    ) -> some View {
        let dayStart = Calendar.current.startOfDay(for: days.first?.date ?? Date())
        let start = dayStart.addingTimeInterval(axis.start)
        let interval = TimelineTicks.tickIntervalMinutes(
            zoom: width / max(viewportWidth, 1),
            spanMinutes: axis.span / 60, viewportWidth: viewportWidth
        )
        return Group {
            if let interval {
                intervalTickLabels(
                    start: start, axis: axis, width: width, intervalMinutes: interval
                )
            } else {
                coarseTickLabels(start: start, span: axis.span)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .frame(width: width, height: Self.ticksHeight, alignment: .topLeading)
    }

    private func coarseTickLabels(start: Date, span: TimeInterval) -> some View {
        HStack {
            Text(Self.hourFormatter.string(from: start))
            Spacer()
            Text(Self.hourFormatter.string(from: start.addingTimeInterval(span / 2)))
            Spacer()
            Text(Self.hourFormatter.string(from: start.addingTimeInterval(span)))
        }
    }

    private func intervalTickLabels(
        start: Date, axis: (start: TimeInterval, span: TimeInterval),
        width: CGFloat, intervalMinutes: Int
    ) -> some View {
        let offsets = TimelineTicks.tickOffsetsMinutes(
            startMinuteOfDay: axis.start / 60,
            spanMinutes: axis.span / 60,
            intervalMinutes: intervalMinutes
        )
        return ZStack(alignment: .topLeading) {
            ForEach(offsets, id: \.self) { offset in
                Text(Self.hourFormatter.string(from: start.addingTimeInterval(offset * 60)))
                    .fixedSize()
                    .position(x: width * offset / (axis.span / 60), y: Self.ticksHeight / 2)
            }
        }
    }
}
