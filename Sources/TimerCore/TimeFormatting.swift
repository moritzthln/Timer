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

    /// "1 h 25 min" above one hour, "45 min" below (whole minutes, floor).
    public static func wording(seconds: Double) -> String {
        let minutes = max(0, Int(seconds) / 60)
        if minutes >= 60 {
            return "\(minutes / 60) h \(minutes % 60) min"
        }
        return "\(minutes) min"
    }

    /// Compact menu bar format: whole minutes rounded up — "25m", and
    /// "1h 5m" from one hour of actual remaining time on (v8).
    public static func compact(seconds: Int) -> String {
        let s = max(0, seconds)
        let minutes = (s + 59) / 60
        if s >= 3600 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}
