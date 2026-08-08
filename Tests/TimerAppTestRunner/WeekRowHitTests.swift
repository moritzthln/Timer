import Foundation
import TimerCore

// v11: WeekRowHit maps a click's y offset in the week timeline's shared
// scroll content to the day row it landed on (rows of `rowHeight` stacked
// with `rowSpacing` gaps), so the single-click day jump can coexist with
// the double-click zoom on one shared surface.

func runWeekRowHitTests() {
    // Geometry of the real week view: 20 pt row blocks, 4 pt gaps, 7 rows.
    let rowHeight = 20.0
    let spacing = 4.0
    let count = 7

    test("clicks inside a row hit that row") {
        try expectEqual(
            WeekRowHit.rowIndex(y: 0, rowHeight: rowHeight, rowSpacing: spacing, rowCount: count),
            0, "top edge of first row"
        )
        try expectEqual(
            WeekRowHit.rowIndex(y: 19.9, rowHeight: rowHeight, rowSpacing: spacing, rowCount: count),
            0, "bottom of first row"
        )
        try expectEqual(
            WeekRowHit.rowIndex(y: 24, rowHeight: rowHeight, rowSpacing: spacing, rowCount: count),
            1, "top edge of second row"
        )
        try expectEqual(
            WeekRowHit.rowIndex(y: 3 * 24 + 10, rowHeight: rowHeight, rowSpacing: spacing, rowCount: count),
            3, "middle of fourth row"
        )
        try expectEqual(
            WeekRowHit.rowIndex(y: 6 * 24 + 19.9, rowHeight: rowHeight, rowSpacing: spacing, rowCount: count),
            6, "bottom of last row"
        )
    }

    test("clicks in the gaps between rows hit nothing") {
        try expectNil(
            WeekRowHit.rowIndex(y: 20, rowHeight: rowHeight, rowSpacing: spacing, rowCount: count),
            "start of first gap"
        )
        try expectNil(
            WeekRowHit.rowIndex(y: 23.9, rowHeight: rowHeight, rowSpacing: spacing, rowCount: count),
            "end of first gap"
        )
    }

    test("clicks outside the rows hit nothing") {
        try expectNil(
            WeekRowHit.rowIndex(y: -0.1, rowHeight: rowHeight, rowSpacing: spacing, rowCount: count),
            "above the first row"
        )
        try expectNil(
            WeekRowHit.rowIndex(y: 6 * 24 + 20, rowHeight: rowHeight, rowSpacing: spacing, rowCount: count),
            "gap above the tick labels"
        )
        try expectNil(
            WeekRowHit.rowIndex(y: 500, rowHeight: rowHeight, rowSpacing: spacing, rowCount: count),
            "far below the rows"
        )
    }

    test("zero spacing packs rows back to back") {
        try expectEqual(
            WeekRowHit.rowIndex(y: 39.9, rowHeight: rowHeight, rowSpacing: 0, rowCount: count),
            1, "end of second row without gaps"
        )
        try expectEqual(
            WeekRowHit.rowIndex(y: 40, rowHeight: rowHeight, rowSpacing: 0, rowCount: count),
            2, "start of third row without gaps"
        )
    }

    test("degenerate geometry hits nothing") {
        try expectNil(
            WeekRowHit.rowIndex(y: 5, rowHeight: 0, rowSpacing: spacing, rowCount: count),
            "zero row height"
        )
        try expectNil(
            WeekRowHit.rowIndex(y: 5, rowHeight: -1, rowSpacing: spacing, rowCount: count),
            "negative row height"
        )
        try expectNil(
            WeekRowHit.rowIndex(y: 5, rowHeight: rowHeight, rowSpacing: -1, rowCount: count),
            "negative spacing"
        )
        try expectNil(
            WeekRowHit.rowIndex(y: 5, rowHeight: rowHeight, rowSpacing: spacing, rowCount: 0),
            "no rows"
        )
        try expectNil(
            WeekRowHit.rowIndex(y: .nan, rowHeight: rowHeight, rowSpacing: spacing, rowCount: count),
            "NaN y"
        )
        try expectNil(
            WeekRowHit.rowIndex(y: .infinity, rowHeight: rowHeight, rowSpacing: spacing, rowCount: count),
            "infinite y"
        )
    }
}
