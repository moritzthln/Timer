import Foundation

/// v20: pure interval subtraction behind the carved activity timeline.
///
/// Since v13 the app list shows a browser minus its promoted seconds
/// (instagram.com / youtube.com as own rows), but the timeline still drew the
/// browser's segments whole — so YouTube time appeared inside the Chrome bar
/// *and* as its own spans. Carving is the fix: every browser app segment
/// minus the promoted spans it contains, remainders in the browser's color,
/// carved-out pieces in the promoted row's color.
public enum SpanCarving {
    /// A drawable time range on a timeline axis — also what
    /// `PromotedSegments` produces (`PromotedSegments.Span` is this type), so
    /// promoted spans can be subtracted without any conversion.
    public struct Span: Equatable, Identifiable {
        public let start: Date
        public let end: Date

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }

        /// Sorted and non-overlapping per source list, so `start` identifies
        /// a span inside one day's list.
        public var id: Date { start }

        /// Zero-length and inverted ranges draw nothing and cut nothing.
        var isEmpty: Bool { end <= start }
    }

    /// `span` minus every cut, applied in order: no overlap keeps the span,
    /// a full cover removes it, an edge overlap leaves one piece, an interior
    /// cut leaves two. Touching boundaries are not overlap (the `FocusClip`
    /// rule), so no zero-length pieces are ever produced. The result stays in
    /// chronological order.
    public static func subtract(span: Span, minus cuts: [Span]) -> [Span] {
        guard !span.isEmpty else { return [] }
        var pieces = [span]
        for cut in cuts where !cut.isEmpty {
            pieces = pieces.flatMap { split($0, by: cut) }
        }
        return pieces
    }

    /// The same subtraction over a whole list — each span carved by the same
    /// cuts, order preserved. The convenience the timelines use when a
    /// segment already arrives in pieces (the focus filter clips first).
    public static func subtract(spans: [Span], minus cuts: [Span]) -> [Span] {
        spans.flatMap { subtract(span: $0, minus: cuts) }
    }

    /// The shared part of two spans, or nil when they miss or only touch —
    /// the carved-out piece a promoted span cuts from an app segment.
    public static func intersection(_ span: Span, _ other: Span) -> Span? {
        let start = max(span.start, other.start)
        let end = min(span.end, other.end)
        return end > start ? Span(start: start, end: end) : nil
    }

    /// Every span ∩ every focus interval, empty intersections dropped — the
    /// "Nur Fokus-Zeit" clip, shared with `PromotedSegments`. Clipping and
    /// carving commute (unit-tested), so the timeline may clip the promoted
    /// spans first and carve with them.
    public static func clip(_ spans: [Span], to intervals: [FocusInterval]) -> [Span] {
        spans.flatMap { span in
            intervals.compactMap {
                intersection(span, Span(start: $0.start, end: $0.end))
            }
        }
    }

    /// One piece minus one cut: unchanged, one side, both sides, or nothing.
    private static func split(_ piece: Span, by cut: Span) -> [Span] {
        guard cut.start < piece.end, cut.end > piece.start else { return [piece] }
        var rest: [Span] = []
        if cut.start > piece.start {
            rest.append(Span(start: piece.start, end: cut.start))
        }
        if cut.end < piece.end {
            rest.append(Span(start: cut.end, end: piece.end))
        }
        return rest
    }
}
