import Foundation
import TimerCore

private func freshSessionStore() -> (store: SessionStore, directory: URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)")
    return (SessionStore(directory: dir), dir)
}

private func ts(_ string: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = TimeZone.current
    return formatter.date(from: string)!
}

func runSessionStoreTests() {
    test("day score is one minus distracted over duration") {
        let (store, _) = freshSessionStore()
        store.append(FocusSessionRecord(
            start: ts("2026-08-07 10:00:00"), end: ts("2026-08-07 10:50:00"),
            distractedSeconds: 300
        ))
        try expectEqual(store.dayScore(for: ts("2026-08-07 12:00:00")) ?? -1,
                        0.9, accuracy: 0.0001, "1 - 300/3000")
    }

    test("day score weights records by duration") {
        let (store, _) = freshSessionStore()
        store.append(FocusSessionRecord(
            start: ts("2026-08-07 09:00:00"), end: ts("2026-08-07 09:10:00"),
            distractedSeconds: 0
        )) // 600 s clean
        store.append(FocusSessionRecord(
            start: ts("2026-08-07 14:00:00"), end: ts("2026-08-07 14:30:00"),
            distractedSeconds: 900
        )) // 1800 s half distracted
        try expectEqual(store.dayScore(for: ts("2026-08-07 12:00:00")) ?? -1,
                        0.625, accuracy: 0.0001, "1 - 900/2400, not the 0.75 average")
    }

    test("no records mean no score") {
        let (store, _) = freshSessionStore()
        try expectNil(store.dayScore(for: ts("2026-08-07 12:00:00")), "empty day")
        try expectNil(store.weekScore(now: ts("2026-08-07 12:00:00")), "empty week")
    }

    test("midnight-crossing record splits with proportional distraction") {
        let (store, _) = freshSessionStore()
        store.append(FocusSessionRecord(
            start: ts("2026-08-06 23:50:00"), end: ts("2026-08-07 00:20:00"),
            distractedSeconds: 600
        )) // 1800 s total: 600 before midnight, 1200 after
        let before = store.records(on: ts("2026-08-06 12:00:00"))
        let after = store.records(on: ts("2026-08-07 12:00:00"))
        try expectEqual(before.count, 1, "one piece before")
        try expectEqual(after.count, 1, "one piece after")
        try expectEqual(before[0].distractedSeconds, 200, accuracy: 0.001, "third of the distraction")
        try expectEqual(after[0].distractedSeconds, 400, accuracy: 0.001, "two thirds")
        try expectEqual(store.dayScore(for: ts("2026-08-06 12:00:00")) ?? -1,
                        1 - 200.0 / 600.0, accuracy: 0.0001, "day score from in-day share")
    }

    test("week score weights the ISO week only") {
        let (store, _) = freshSessionStore()
        // 2026-08-07 is a Friday; its ISO week runs Mon 08-03 ... Sun 08-09.
        store.append(FocusSessionRecord(
            start: ts("2026-08-03 09:00:00"), end: ts("2026-08-03 09:30:00"),
            distractedSeconds: 0
        )) // 1800 s clean
        store.append(FocusSessionRecord(
            start: ts("2026-08-07 09:00:00"), end: ts("2026-08-07 09:10:00"),
            distractedSeconds: 300
        )) // 600 s half distracted
        store.append(FocusSessionRecord(
            start: ts("2026-08-02 09:00:00"), end: ts("2026-08-02 09:10:00"),
            distractedSeconds: 600
        )) // Sunday before → previous week, ignored
        try expectEqual(store.weekScore(now: ts("2026-08-07 12:00:00")) ?? -1,
                        1 - 300.0 / 2400.0, accuracy: 0.0001, "Mon+Fri weighted")
    }

    test("invalid records and corrupt files read as empty") {
        let (store, directory) = freshSessionStore()
        store.append(FocusSessionRecord(
            start: ts("2026-08-07 10:00:00"), end: ts("2026-08-07 10:00:00"),
            distractedSeconds: 0
        )) // zero duration: dropped
        try expectNil(store.dayScore(for: ts("2026-08-07 12:00:00")), "dropped")
        try Data("not json".utf8).write(to: directory.appendingPathComponent("2026-08-05.json"))
        try expectEqual(store.records(on: ts("2026-08-05 12:00:00")), [], "corrupt file reads empty")
    }
}
