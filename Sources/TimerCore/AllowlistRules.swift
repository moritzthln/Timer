import Foundation

/// v15 allowlist semantics: while the shield runs in allowlist mode, regular
/// user apps not on the list terminate and browser tabs on unlisted hosts
/// close. Each arm guards independently against an empty list — an empty
/// allowlist blocks nothing (instead of everything).
public enum AllowlistRules {
    /// Always implicitly allowed, so the machine stays operable: the Timer
    /// itself, Finder, and System Settings.
    public static let essentialBundleIDs: Set<String> = [
        "com.moritzthelen.timer",
        "com.apple.finder",
        "com.apple.systempreferences",
    ]

    /// True iff the app should be terminated: not allowed and not essential.
    /// Callers pre-filter to regular user apps — the activation policy is an
    /// AppKit concept the pure rule cannot see. With zero allowed apps the
    /// app arm never engages.
    public static func shouldTerminate(
        bundleID: String,
        allowed: Set<String>,
        essential: Set<String> = essentialBundleIDs
    ) -> Bool {
        guard !allowed.isEmpty else { return false }
        return !allowed.contains(bundleID) && !essential.contains(bundleID)
    }

    /// True iff the browser's current tab should close: the host is present
    /// and matches no allowed domain (suffix semantics like the blocklist).
    /// Internal/blank pages (nil or empty host, e.g. new tabs) are never
    /// closed; with zero allowed domains the tab arm never engages.
    public static func shouldCloseTab(host: String?, allowedDomains: [String]) -> Bool {
        guard !allowedDomains.isEmpty, let host, !host.isEmpty else { return false }
        return !allowedDomains.contains { FocusBlockRules.domainMatches(host: host, entry: $0) }
    }
}
