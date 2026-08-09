import Foundation

/// v22: a blocked tab is covered first and only switched away from if the user
/// stays. This is the pure decision for one poll tick of the frontmost
/// browser — the caller supplies the blocked host it just read (nil when the
/// active tab is fine), plus which host is covered right now and since when.
///
/// The cover is the friendly half of the ladder: it explains itself and leaves
/// the browser chrome usable, so leaving on your own is always the cheaper
/// option. Only staying costs the tab switch.
public enum SiteCoverPlan {
    public enum Decision: Equatable {
        /// Raise the cover for this host and start its clock.
        case cover(host: String)
        /// The same host is still up front and inside the grace — refresh the
        /// countdown, leave the clock alone.
        case keepCovering
        /// The grace is over: run the v16 tab switch and take the cover down.
        case switchAway
        /// Nothing (blocked) to cover — take any cover down. Idempotent, so it
        /// is also the answer while nothing is covered at all.
        case dropCover
    }

    /// How long the user gets to leave the blocked tab himself.
    public static let defaultThreshold: TimeInterval = 10

    /// The next step. A different blocked host is a fresh sight, so its clock
    /// restarts instead of inheriting the previous host's age — otherwise
    /// hopping between two blocked sites would switch away instantly. A
    /// covered host without a start time (state that cannot happen through
    /// this module, but the caller owns it) restarts as well: covering once
    /// more is harmless, switching away out of nowhere is not.
    public static func next(
        host: String?,
        coveredHost: String?,
        coveredSince: Date?,
        now: Date,
        threshold: TimeInterval = defaultThreshold
    ) -> Decision {
        guard let host else { return .dropCover }
        guard coveredHost == host, let coveredSince else { return .cover(host: host) }
        return now.timeIntervalSince(coveredSince) >= threshold ? .switchAway : .keepCovering
    }
}
