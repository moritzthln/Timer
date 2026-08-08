import Foundation

/// How an app counts toward focus quality.
public enum AppCategory: String, Codable, CaseIterable, Equatable {
    case productive
    case neutral
    case distracting

    /// Resolution order for a bundle ID: explicit user choice, else
    /// distracting when the bundle is on the v3 focus blocklist, else neutral.
    public static func resolve(
        bundleID: String,
        explicit: [String: AppCategory],
        blockedBundleIDs: Set<String>
    ) -> AppCategory {
        if let category = explicit[bundleID] { return category }
        if blockedBundleIDs.contains(bundleID) { return .distracting }
        return .neutral
    }
}
