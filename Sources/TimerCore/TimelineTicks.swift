import Foundation

/// v9: adaptive tick spacing for the zoomable activity timeline. Pure layout
/// math — the view supplies zoom, span, and viewport width and renders
/// whatever interval comes back.
public enum TimelineTicks {
    public static let minZoom: Double = 1
    public static let maxZoom: Double = 16

    /// An hourly label needs at least this many points per hour.
    private static let hourlyMinPoints: Double = 60
    /// A quarter-hourly label needs at least this many points per quarter hour.
    private static let quarterHourlyMinPoints: Double = 50

    /// The tick interval in minutes: 15 (quarter-hourly) or 60 (hourly), or
    /// nil for the coarse start/mid/end labels. 1× is always coarse (the
    /// unzoomed timeline keeps its v4 look regardless of window width);
    /// zoomed in, the finest interval whose labels still fit wins. Zoom is
    /// clamped to 1–16; degenerate spans and widths fall back to coarse.
    public static func tickIntervalMinutes(
        zoom: Double, spanMinutes: Double, viewportWidth: Double
    ) -> Int? {
        let clampedZoom = min(max(zoom, minZoom), maxZoom)
        guard clampedZoom > 1, spanMinutes > 0, viewportWidth > 0,
              spanMinutes.isFinite, viewportWidth.isFinite else { return nil }
        let pointsPerMinute = viewportWidth * clampedZoom / spanMinutes
        if 15 * pointsPerMinute >= quarterHourlyMinPoints { return 15 }
        if 60 * pointsPerMinute >= hourlyMinPoints { return 60 }
        return nil
    }

    /// Offsets in minutes from the span start for every wall-clock multiple
    /// of `intervalMinutes` inside the span (boundaries included), so labels
    /// read "10:00", "10:15", … instead of arbitrary times. `startMinuteOfDay`
    /// is the span start as minutes since local midnight.
    public static func tickOffsetsMinutes(
        startMinuteOfDay: Double, spanMinutes: Double, intervalMinutes: Int
    ) -> [Double] {
        guard intervalMinutes > 0, spanMinutes > 0,
              startMinuteOfDay.isFinite, spanMinutes.isFinite else { return [] }
        let interval = Double(intervalMinutes)
        var tick = (startMinuteOfDay / interval).rounded(.up) * interval
        var offsets: [Double] = []
        while tick <= startMinuteOfDay + spanMinutes {
            offsets.append(tick - startMinuteOfDay)
            tick += interval
        }
        return offsets
    }
}
