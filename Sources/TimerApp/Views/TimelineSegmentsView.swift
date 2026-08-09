import SwiftUI
import TimerCore

/// v19: one drawable rect of an activity timeline — offsets in seconds from
/// the axis origin plus how to paint it. App segments and promoted-site spans
/// differ only in their source list and color, so both become spans and run
/// through the same rect math (and therefore the same zoom math).
struct TimelineSpan: Identifiable {
    let id: String
    let startOffset: TimeInterval
    let endOffset: TimeInterval
    let color: Color
    let opacity: Double
    /// nil = no tooltip (the week rows' app segments, v10).
    let tooltip: String?

    /// v10 drill-down: everything but the selection fades to this.
    static let dimmedOpacity: Double = 0.15
}

/// v19: the shared segment layer of the day timeline and the week rows —
/// extracted so the promoted-site highlight is drawn by exactly the same code
/// (and lands on exactly the same axis) as the app segments beneath it.
struct TimelineSegmentsView: View {
    let spans: [TimelineSpan]
    /// Length of the drawn axis in seconds (what `width` represents).
    let axisSpan: TimeInterval
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            if axisSpan > 0 {
                ForEach(spans) { rect($0) }
            }
        }
        .frame(width: width, height: height, alignment: .leading)
    }

    @ViewBuilder
    private func rect(_ span: TimelineSpan) -> some View {
        let bar = Rectangle()
            .fill(span.color)
            .opacity(span.opacity)
            .frame(width: max(1, width * CGFloat((span.endOffset - span.startOffset) / axisSpan)))
            .offset(x: width * CGFloat(span.startOffset / axisSpan))
        if let tooltip = span.tooltip {
            bar.help(tooltip)
        } else {
            bar
        }
    }
}

// MARK: - Span sources

extension TimelineSpan {
    /// A day's app segments as spans on an axis starting at `origin`: palette
    /// color per bundle id and the v10 drill-down dimming. A promoted website
    /// selection matches no bundle id, so it dims every app segment — exactly
    /// the v19 backdrop for the highlight layer.
    static func apps(
        _ summary: DaySummary, origin: Date, selectedID: String?,
        colorFor: (String) -> Color, tooltips: Bool
    ) -> [TimelineSpan] {
        summary.apps.flatMap(\.segments).compactMap { segment -> TimelineSpan? in
            guard case .app(let bundleID, let name) = segment.kind else { return nil }
            return TimelineSpan(
                id: segment.id.uuidString,
                startOffset: segment.start.timeIntervalSince(origin),
                endOffset: segment.end.timeIntervalSince(origin),
                color: colorFor(bundleID),
                opacity: selectedID == nil || selectedID == bundleID ? 1 : dimmedOpacity,
                tooltip: tooltips
                    ? TimelineClock.tooltip(name: name, start: segment.start, end: segment.end)
                    : nil
            )
        }
    }

    /// v19: the selected promoted row's site spans — cross-browser, subdomains
    /// included, merged, and (with "Nur Fokus-Zeit" on) clipped to `clip` —
    /// at full opacity in the row's palette color.
    static func promotedSites(
        _ summary: DaySummary, origin: Date, domain: String, promoted: [String],
        clip: [FocusInterval]?, color: Color, tooltips: Bool
    ) -> [TimelineSpan] {
        PromotedSegments.spans(
            siteSegments: summary.siteSegments, domain: domain,
            promoted: promoted, clippedTo: clip
        ).map { span in
            TimelineSpan(
                id: "\(domain)@\(span.start.timeIntervalSinceReferenceDate)",
                startOffset: span.start.timeIntervalSince(origin),
                endOffset: span.end.timeIntervalSince(origin),
                color: color, opacity: 1,
                tooltip: tooltips
                    ? TimelineClock.tooltip(name: domain, start: span.start, end: span.end)
                    : nil
            )
        }
    }
}

/// The timelines' shared "H:mm" clock: tick labels, segment tooltips, and the
/// v19 site-span tooltips all read the same way.
enum TimelineClock {
    static let hour: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    /// "Safari · 9:12–9:47 (35 min)" — also "youtube.com · 14:02–14:31
    /// (29 min)" for a promoted row's spans. Presence gaps draw no rect, so
    /// they naturally get no tooltip.
    static func tooltip(name: String, start: Date, end: Date) -> String {
        let duration = TimeFormatting.wording(seconds: end.timeIntervalSince(start))
        return "\(name) · \(hour.string(from: start))–\(hour.string(from: end)) (\(duration))"
    }
}
