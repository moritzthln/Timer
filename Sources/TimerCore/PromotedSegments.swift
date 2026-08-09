import Foundation

/// v19: the drawable spans behind a promoted website's timeline drill-down.
/// Pure math over a day's raw site segments: pick the ones the selected
/// promoted row owns (subdomains included, all browsers merged), optionally
/// clip them to the day's focus intervals ("Nur Fokus-Zeit"), and hand back
/// one sorted, non-overlapping list the timelines can draw like app segments.
public enum PromotedSegments {
    /// A drawable time range on a timeline axis. Sorted and non-overlapping
    /// by construction, so `start` identifies it inside one day's list.
    /// v20: the shared span type — these spans are what carves the browsers'
    /// app segments, so both sides speak the same currency.
    public typealias Span = SpanCarving.Span

    /// The spans of `domain` in one day's site segments.
    ///
    /// Ownership follows the v13 row totals: a segment belongs to `domain`
    /// exactly when `domain` is the first entry of `promoted` its host
    /// matches (`FocusBlockRules.domainMatches`, so subdomains count). An
    /// empty `promoted` means "match `domain` itself" — the same rule with
    /// a one-entry list.
    ///
    /// `clip` non-nil keeps only the overlap with those focus intervals
    /// (`FocusClip` semantics: touching boundaries are not overlap); nil
    /// keeps the full durations. Pieces that touch or overlap after that
    /// collapse into one span — consecutive subdomains and browser switches
    /// read as the single visit they were.
    public static func spans(
        siteSegments: [ActivitySegment],
        domain: String,
        promoted: [String] = [],
        clippedTo clip: [FocusInterval]? = nil
    ) -> [Span] {
        let list = promoted.isEmpty ? [domain] : promoted
        let owned = siteSegments.compactMap { segment -> Span? in
            guard case .site(let host, _) = segment.kind,
                  segment.end > segment.start,
                  SitePromotion.firstMatch(host: host, promoted: list) == domain
            else { return nil }
            return Span(start: segment.start, end: segment.end)
        }
        return merged(clip.map { SpanCarving.clip(owned, to: $0) } ?? owned)
    }

    /// Sorts by start and coalesces touching or overlapping spans.
    private static func merged(_ spans: [Span]) -> [Span] {
        var result: [Span] = []
        for span in spans.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, span.start <= last.end {
                result[result.count - 1] = Span(
                    start: last.start, end: max(last.end, span.end)
                )
            } else {
                result.append(span)
            }
        }
        return result
    }
}
