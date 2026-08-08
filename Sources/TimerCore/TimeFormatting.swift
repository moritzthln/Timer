import Foundation

public enum TimeFormatting {
    /// "m:ss" below one hour (5:00, 24:37), "h:mm:ss" at or above (1:05:00).
    public static func format(seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
