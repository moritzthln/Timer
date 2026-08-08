import Foundation

/// v14: usage-share labels for the activity app list — a row's fraction of
/// the displayed period's total, rendered German-style with a regular space
/// before the percent sign ("39 %", matching "1 h 25 min").
public enum UsageShare {
    /// Whole-percent share label. Halves round up ("half away from zero"),
    /// shares > 0 but < 0.5 % render "<1 %" instead of a misleading "0 %".
    /// No label (nil) when the basis or the row itself is zero.
    public static func percentLabel(seconds: Double, total: Double) -> String? {
        guard total > 0, seconds > 0 else { return nil }
        let percent = seconds / total * 100
        guard percent >= 0.5 else { return "<1 %" }
        return "\(Int(percent.rounded())) %"
    }
}
