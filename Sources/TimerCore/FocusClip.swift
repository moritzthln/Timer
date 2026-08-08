import Foundation

/// v12: pure overlap math behind the "Nur Fokus-Zeit" filter.
public enum FocusClip {
    /// Total overlap (seconds) of one segment with a list of focus
    /// intervals. The intervals are non-overlapping by construction
    /// (FocusLog), so plain summing never double-counts; touching
    /// boundaries and zero-length pieces contribute nothing.
    public static func clippedSeconds(
        segmentStart: Date, segmentEnd: Date, intervals: [FocusInterval]
    ) -> Double {
        guard segmentEnd > segmentStart else { return 0 }
        return intervals.reduce(0) { total, interval in
            let start = max(segmentStart, interval.start)
            let end = min(segmentEnd, interval.end)
            return end > start ? total + end.timeIntervalSince(start) : total
        }
    }
}
