import Foundation
import TimerCore

/// Augments persisted focus intervals with the currently running session,
/// which only reaches the FocusLog when its segment ends (v12.1 fix: the
/// focus-only filter looked empty while a timer was still running).
enum LiveFocus {
    static func augment(
        _ intervals: [FocusInterval], onDay day: Date, liveStart: Date?
    ) -> [FocusInterval] {
        guard let liveStart,
              Calendar.current.isDate(day, inSameDayAs: Date()) else {
            return intervals
        }
        let now = Date()
        guard now > liveStart else { return intervals }
        return intervals + [FocusInterval(start: liveStart, end: now)]
    }
}
