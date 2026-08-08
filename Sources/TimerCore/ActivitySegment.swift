import Foundation

public struct ActivitySegment: Codable, Equatable, Identifiable {
    public enum Kind: Codable, Equatable {
        case presence
        case app(bundleID: String, name: String)
        case site(domain: String, browserBundleID: String)
    }

    public let id: UUID
    public var kind: Kind
    public var start: Date
    public var end: Date

    public init(id: UUID = UUID(), kind: Kind, start: Date, end: Date) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
    }

    /// Lowercases and strips one leading "www." — display/aggregation key.
    public static func normalizeHost(_ host: String) -> String {
        let lowered = host.lowercased()
        if lowered.hasPrefix("www.") {
            return String(lowered.dropFirst(4))
        }
        return lowered
    }
}
