import Foundation

/// v20: which promoted domain owns which spans inside which browser — the
/// table that carves the browsers' app segments in the activity timeline.
/// Built once per drawn timeline (the day bar, and one per week row) and
/// consulted per app segment.
///
/// Spans stay grouped per browser, exactly like the list's per-browser
/// reduction (v13), so Chrome's YouTube time never carves Safari's bar.
/// Ownership is the v13 first-match-wins rule and the optional clip is the
/// "Nur Fokus-Zeit" filter — both come from `PromotedSegments`. Clipping the
/// spans before carving is safe: clip and carve commute (`SpanCarving`).
public struct PromotedCarve {
    /// One promoted domain and the spans it owns inside one browser.
    public struct Entry: Equatable {
        public let domain: String
        public let spans: [SpanCarving.Span]

        public init(domain: String, spans: [SpanCarving.Span]) {
            self.domain = domain
            self.spans = spans
        }
    }

    /// Browser bundle id → its promoted spans, in promoted-list order.
    /// Empty whenever nothing is promoted or nothing promoted was visited.
    private let table: [String: [Entry]]

    public init(summary: DaySummary, promoted: [String], clippedTo clip: [FocusInterval]?) {
        self.init(siteSegments: summary.siteSegments, promoted: promoted, clippedTo: clip)
    }

    public init(
        siteSegments: [ActivitySegment], promoted: [String], clippedTo clip: [FocusInterval]?
    ) {
        guard !promoted.isEmpty else {
            table = [:]
            return
        }
        var table: [String: [Entry]] = [:]
        for (browser, segments) in Dictionary(grouping: siteSegments, by: Self.browser(of:)) {
            guard let browser else { continue }
            let entries = promoted.compactMap { domain -> Entry? in
                let spans = PromotedSegments.spans(
                    siteSegments: segments, domain: domain,
                    promoted: promoted, clippedTo: clip
                )
                return spans.isEmpty ? nil : Entry(domain: domain, spans: spans)
            }
            if !entries.isEmpty { table[browser] = entries }
        }
        self.table = table
    }

    /// Everything promoted inside `browser` — what its app segments are cut
    /// by. Non-browser bundle ids simply have nothing to subtract.
    public func cuts(browser: String) -> [SpanCarving.Span] {
        (table[browser] ?? []).flatMap(\.spans)
    }

    /// The carved-out pieces of `span`, each tagged with the promoted domain
    /// that owns it (and therefore with its list row's color and label).
    /// Entries without a piece inside `span` drop out.
    public func pieces(browser: String, in span: SpanCarving.Span) -> [Entry] {
        (table[browser] ?? []).compactMap { entry in
            let pieces = entry.spans.compactMap { SpanCarving.intersection(span, $0) }
            return pieces.isEmpty ? nil : Entry(domain: entry.domain, spans: pieces)
        }
    }

    private static func browser(of segment: ActivitySegment) -> String? {
        guard case .site(_, let browser) = segment.kind else { return nil }
        return browser
    }
}
