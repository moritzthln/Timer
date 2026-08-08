import Foundation

/// v10: week-consistent app coloring. The week view ranks apps over the whole
/// week's totals so the same app keeps the same palette index in all seven
/// rows (the day view keeps its per-day ranking).
public enum WeekRanking {
    /// Rank index per bundle id: 0 for the largest total, ascending from
    /// there. Equal totals tie-break by bundle id so colors are stable
    /// across reloads.
    public static func rank(appTotals: [String: Double]) -> [String: Int] {
        let ordered = appTotals.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
        }
        var ranks: [String: Int] = [:]
        for (index, entry) in ordered.enumerated() {
            ranks[entry.key] = index
        }
        return ranks
    }
}
