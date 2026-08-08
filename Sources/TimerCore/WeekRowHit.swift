import Foundation

/// v11: pure hit-testing for the week timeline's stacked day rows — maps a
/// click's y offset (shared scroll-content coordinates) to the row index it
/// landed on, so the single-click day jump can live on the same zoomable
/// surface as the double-click zoom. Clicks in the gaps between rows and
/// outside the row block (e.g. the tick labels) hit nothing.
public enum WeekRowHit {
    public static func rowIndex(
        y: Double, rowHeight: Double, rowSpacing: Double, rowCount: Int
    ) -> Int? {
        guard rowHeight > 0, rowHeight.isFinite,
              rowSpacing >= 0, rowSpacing.isFinite,
              rowCount > 0, y.isFinite, y >= 0 else { return nil }
        let period = rowHeight + rowSpacing
        let index = (y / period).rounded(.down)
        guard index < Double(rowCount) else { return nil }
        // Inside the row itself, not in the gap below it.
        guard y - index * period < rowHeight else { return nil }
        return Int(index)
    }
}
