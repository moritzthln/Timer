import Foundation
import TimerCore

private func freshFocusLog() -> (log: FocusLog, dir: URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("FocusLogTests-\(UUID().uuidString)")
    return (FocusLog(directory: dir), dir)
}

private func ts(_ string: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = TimeZone.current
    return formatter.date(from: string)!
}

func runFocusLogTests() {
    test("appended interval reads back on its day") {
        let (log, _) = freshFocusLog()
        log.append(start: ts("2026-08-07 14:02:00"), end: ts("2026-08-07 14:31:00"))
        let intervals = log.intervals(onDay: ts("2026-08-07 18:00:00"))
        try expectEqual(intervals.count, 1, "one interval")
        try expectEqual(intervals[0].start, ts("2026-08-07 14:02:00"), "start")
        try expectEqual(intervals[0].end, ts("2026-08-07 14:31:00"), "end")
    }

    test("intervals come back sorted by start") {
        let (log, _) = freshFocusLog()
        log.append(start: ts("2026-08-07 15:00:00"), end: ts("2026-08-07 15:25:00"))
        log.append(start: ts("2026-08-07 09:00:00"), end: ts("2026-08-07 09:50:00"))
        log.append(start: ts("2026-08-07 11:30:00"), end: ts("2026-08-07 12:00:00"))
        let intervals = log.intervals(onDay: ts("2026-08-07 12:00:00"))
        try expectEqual(intervals.count, 3, "three intervals")
        try expectEqual(intervals.map(\.start), [
            ts("2026-08-07 09:00:00"), ts("2026-08-07 11:30:00"), ts("2026-08-07 15:00:00"),
        ], "sorted by start")
    }

    test("midnight-crossing interval splits into both day files") {
        let (log, _) = freshFocusLog()
        log.append(start: ts("2026-08-06 23:50:00"), end: ts("2026-08-07 00:20:00"))
        let before = log.intervals(onDay: ts("2026-08-06 12:00:00"))
        let after = log.intervals(onDay: ts("2026-08-07 12:00:00"))
        try expectEqual(before.count, 1, "piece before midnight")
        try expectEqual(before[0].start, ts("2026-08-06 23:50:00"), "piece start")
        try expectEqual(before[0].end, ts("2026-08-07 00:00:00"), "cut at midnight")
        try expectEqual(after.count, 1, "piece after midnight")
        try expectEqual(after[0].start, ts("2026-08-07 00:00:00"), "resumes at midnight")
        try expectEqual(after[0].end, ts("2026-08-07 00:20:00"), "piece end")
    }

    test("end at or before start is discarded") {
        let (log, _) = freshFocusLog()
        log.append(start: ts("2026-08-07 10:00:00"), end: ts("2026-08-07 10:00:00"))
        log.append(start: ts("2026-08-07 10:00:00"), end: ts("2026-08-07 09:00:00"))
        try expectEqual(log.intervals(onDay: ts("2026-08-07 12:00:00")).count, 0, "discarded")
    }

    test("missing day file reads as empty") {
        let (log, _) = freshFocusLog()
        try expectEqual(log.intervals(onDay: ts("2026-08-07 12:00:00")).count, 0, "empty")
    }

    test("corrupt day file reads as empty") {
        let (log, dir) = freshFocusLog()
        log.append(start: ts("2026-08-07 10:00:00"), end: ts("2026-08-07 10:30:00"))
        let file = dir.appendingPathComponent("2026-08-07.json")
        try Data("not json{".utf8).write(to: file)
        try expectEqual(log.intervals(onDay: ts("2026-08-07 12:00:00")).count, 0, "empty on corrupt")
    }

    test("appends on the same day accumulate") {
        let (log, _) = freshFocusLog()
        log.append(start: ts("2026-08-07 10:00:00"), end: ts("2026-08-07 10:25:00"))
        log.append(start: ts("2026-08-07 14:00:00"), end: ts("2026-08-07 14:25:00"))
        try expectEqual(log.intervals(onDay: ts("2026-08-07 12:00:00")).count, 2, "both kept")
    }

    test("default directory ends in Timer/focus") {
        let path = FocusLog.defaultDirectory().path
        try expect(path.hasSuffix("Timer/focus"), "got \(path)")
    }
}
