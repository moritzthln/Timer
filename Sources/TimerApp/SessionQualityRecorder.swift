import Foundation
import TimerCore

/// Turns a finished focus segment into a quality record: query the activity
/// store for overlapping app segments (already clipped to the window) and
/// sum the time spent in apps that resolve to `.distracting`.
///
/// The caller must flush the activity tracker first (`flushNow()`) so the
/// open app segment's latest minute is persisted before the query runs.
final class SessionQualityRecorder {
    private let activity: ActivityStore
    private let sessions: SessionStore
    private let preferences: Preferences

    init(activity: ActivityStore, sessions: SessionStore, preferences: Preferences) {
        self.activity = activity
        self.sessions = sessions
        self.preferences = preferences
    }

    func record(start: Date, end: Date) {
        guard end > start else { return } // zero-duration window: record skipped
        let categories = preferences.appCategories
        let blocked = Set(preferences.blockedApps.map(\.bundleID))
        let window = DateInterval(start: start, end: end)
        let distracted = activity.appSegments(overlapping: window).reduce(0.0) { total, segment in
            guard case .app(let bundleID, _) = segment.kind,
                  AppCategory.resolve(
                      bundleID: bundleID, explicit: categories, blockedBundleIDs: blocked
                  ) == .distracting else {
                return total
            }
            return total + segment.end.timeIntervalSince(segment.start)
        }
        sessions.append(FocusSessionRecord(start: start, end: end, distractedSeconds: distracted))
    }
}
