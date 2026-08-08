import Foundation
import TimerCore

private func freshActivityStore() -> ActivityStore {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ActivityStoreTests-\(UUID().uuidString)")
    return ActivityStore(directory: dir)
}

private func ts(_ string: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = TimeZone.current
    return formatter.date(from: string)!
}

func runActivityStoreTests() {
    test("appended app segments aggregate into the day summary") {
        let store = freshActivityStore()
        store.append(ActivitySegment(
            kind: .app(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
            start: ts("2026-08-07 10:00:00"), end: ts("2026-08-07 10:30:00")
        ))
        store.append(ActivitySegment(
            kind: .app(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
            start: ts("2026-08-07 11:00:00"), end: ts("2026-08-07 11:15:00")
        ))
        let summary = store.daySummary(for: ts("2026-08-07 12:00:00"))
        try expectEqual(summary.apps.count, 1, "one app")
        try expectEqual(summary.apps[0].name, "Xcode", "name")
        try expectEqual(summary.apps[0].totalSeconds, 2700, accuracy: 0.5, "45 min")
        try expectEqual(summary.apps[0].segments.count, 2, "two segments kept for timeline")
    }

    test("presence spans define first, last, and active total") {
        let store = freshActivityStore()
        store.append(ActivitySegment(kind: .presence, start: ts("2026-08-07 09:12:00"), end: ts("2026-08-07 12:00:00")))
        store.append(ActivitySegment(kind: .presence, start: ts("2026-08-07 13:00:00"), end: ts("2026-08-07 17:43:00")))
        let summary = store.daySummary(for: ts("2026-08-07 12:00:00"))
        try expectEqual(summary.firstActivity, ts("2026-08-07 09:12:00"), "first")
        try expectEqual(summary.lastActivity, ts("2026-08-07 17:43:00"), "last")
        try expectEqual(summary.presenceSeconds, (168 * 60 + 283 * 60) * 1.0, accuracy: 0.5, "2:48 + 4:43")
    }

    test("midnight-crossing segment splits into both day files") {
        let store = freshActivityStore()
        store.append(ActivitySegment(
            kind: .app(bundleID: "a", name: "A"),
            start: ts("2026-08-06 23:50:00"), end: ts("2026-08-07 00:20:00")
        ))
        try expectEqual(store.daySummary(for: ts("2026-08-06 12:00:00")).apps[0].totalSeconds, 600, accuracy: 0.5, "before midnight")
        try expectEqual(store.daySummary(for: ts("2026-08-07 12:00:00")).apps[0].totalSeconds, 1200, accuracy: 0.5, "after midnight")
    }

    test("upsert replaces a segment by id instead of duplicating") {
        let store = freshActivityStore()
        let id = UUID()
        store.upsert(ActivitySegment(id: id, kind: .presence, start: ts("2026-08-07 09:00:00"), end: ts("2026-08-07 09:10:00")))
        store.upsert(ActivitySegment(id: id, kind: .presence, start: ts("2026-08-07 09:00:00"), end: ts("2026-08-07 09:20:00")))
        let summary = store.daySummary(for: ts("2026-08-07 12:00:00"))
        try expectEqual(summary.presenceSeconds, 1200, accuracy: 0.5, "20 min once")
    }

    test("site segments group by browser and domain") {
        let store = freshActivityStore()
        store.append(ActivitySegment(
            kind: .site(domain: "youtube.com", browserBundleID: "com.google.Chrome"),
            start: ts("2026-08-07 10:00:00"), end: ts("2026-08-07 10:10:00")
        ))
        store.append(ActivitySegment(
            kind: .site(domain: "youtube.com", browserBundleID: "com.google.Chrome"),
            start: ts("2026-08-07 11:00:00"), end: ts("2026-08-07 11:05:00")
        ))
        store.append(ActivitySegment(
            kind: .site(domain: "github.com", browserBundleID: "com.google.Chrome"),
            start: ts("2026-08-07 12:00:00"), end: ts("2026-08-07 12:20:00")
        ))
        let summary = store.daySummary(for: ts("2026-08-07 12:00:00"))
        let chrome = summary.sitesByBrowser["com.google.Chrome"] ?? []
        try expectEqual(chrome.count, 2, "two domains")
        try expectEqual(chrome[0].domain, "github.com", "sorted by time desc")
        try expectEqual(chrome[0].totalSeconds, 1200, accuracy: 0.5, "20 min")
        try expectEqual(chrome[1].totalSeconds, 900, accuracy: 0.5, "15 min")
    }

    test("invalid and unreadable data reads as empty day") {
        let store = freshActivityStore()
        store.append(ActivitySegment(kind: .presence, start: ts("2026-08-07 10:00:00"), end: ts("2026-08-07 09:00:00"))) // end < start: discarded
        let summary = store.daySummary(for: ts("2026-08-07 12:00:00"))
        try expectEqual(summary.presenceSeconds, 0, accuracy: 0.5, "discarded")
        try expectNil(summary.firstActivity, "empty day")
    }
}
