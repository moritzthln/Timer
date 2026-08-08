import SwiftUI

/// v11: focus intervals drawn directly on a timeline bar — an accent wash
/// (~12 % opacity) across the full bar height plus 1 pt accent edge lines
/// at each interval's start and end, so focus windows and app segments
/// overlap visually. Drawn on top of the segments (they stay readable
/// beneath the low-opacity wash; drill-down dimming multiplies underneath)
/// and never hit-testable, so the segment tooltips keep working.
struct FocusBarOverlay: View {
    /// Clamped (start, end) fractions of the bar width, each in 0...1.
    let fractions: [(start: CGFloat, end: CGFloat)]
    let width: CGFloat

    private static let washOpacity = 0.12
    private static let edgeWidth: CGFloat = 1

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(fractions.indices, id: \.self) { index in
                wash(fractions[index])
                edge(at: fractions[index].start)
                edge(at: fractions[index].end)
            }
        }
        .allowsHitTesting(false)
    }

    private func wash(_ fraction: (start: CGFloat, end: CGFloat)) -> some View {
        Rectangle()
            .fill(Color.accentColor.opacity(Self.washOpacity))
            .frame(width: max(Self.edgeWidth, width * (fraction.end - fraction.start)))
            .offset(x: width * fraction.start)
    }

    /// A 1 pt vertical line, kept inside the bar even at the far edge.
    private func edge(at fraction: CGFloat) -> some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: Self.edgeWidth)
            .offset(x: min(width * fraction, max(width - Self.edgeWidth, 0)))
    }

    /// The interval [startOffset, endOffset] (seconds on the bar's axis)
    /// clamped to [0, span] as width fractions, or nil when it misses the
    /// axis entirely. Shared by the overlays and the under-bar traces.
    static func clampedFractions(
        startOffset: TimeInterval, endOffset: TimeInterval, span: TimeInterval
    ) -> (start: CGFloat, end: CGFloat)? {
        guard span > 0 else { return nil }
        let start = max(0, startOffset)
        let end = min(span, endOffset)
        guard end > start else { return nil }
        return (CGFloat(start / span), CGFloat(end / span))
    }
}

/// v12: the inverse of the overlay — a rendering mask for the segment layer
/// that keeps focus regions at full strength and multiplies everything
/// outside down to ~0.15 (so it combines multiplicatively with the
/// drill-down dimming). Applied to the segments only; the track background,
/// the wash and the edge lines stay as they are. With no fractions the whole
/// layer dims — the filtered empty state.
struct FocusDimMask: View {
    /// Clamped (start, end) fractions of the bar width, each in 0...1.
    let fractions: [(start: CGFloat, end: CGFloat)]
    let width: CGFloat

    static let outsideOpacity = 0.15

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(Self.outsideOpacity))
            ForEach(fractions.indices, id: \.self) { index in
                Rectangle()
                    .fill(Color.white)
                    .frame(width: max(1, width * (fractions[index].end - fractions[index].start)))
                    .offset(x: width * fractions[index].start)
            }
        }
    }
}
