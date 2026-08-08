import Foundation

/// Absolute heatmap intensity: a day is shaded relative to the busiest day of
/// the visible period, not to a configured goal (v8 removed the daily goal).
public enum HeatmapScale {
    /// Level 0–4: nothing · >0 · ≥25 % · ≥50 % · ≥75 % of `maxSeconds`.
    /// `maxSeconds` is the maximum day total of the visible period; it always
    /// includes the day itself, so a degenerate non-positive max with positive
    /// seconds only guards the division and maps to full intensity.
    public static func level(seconds: Double, maxSeconds: Double) -> Int {
        guard seconds > 0 else { return 0 }
        guard maxSeconds > 0 else { return 4 }
        let ratio = seconds / maxSeconds
        if ratio >= 0.75 { return 4 }
        if ratio >= 0.5 { return 3 }
        if ratio >= 0.25 { return 2 }
        return 1
    }
}
