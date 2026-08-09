import Foundation

/// v16 restore tracking: the block controller records the bundle ids of the
/// apps *it* hid, so deactivation can unhide exactly those and nothing else
/// (apps the user hid manually are never touched).
public struct HiddenAppsRecord {
    private var bundleIDs: Set<String> = []

    public init() {}

    public var isEmpty: Bool { bundleIDs.isEmpty }

    /// Records one hidden app; idempotent (re-hiding an already recorded
    /// app keeps a single entry).
    public mutating func add(_ bundleID: String) {
        bundleIDs.insert(bundleID)
    }

    /// Returns everything recorded and clears the record.
    public mutating func drain() -> Set<String> {
        defer { bundleIDs = [] }
        return bundleIDs
    }
}
