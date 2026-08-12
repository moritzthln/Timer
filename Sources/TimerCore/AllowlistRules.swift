import Foundation

/// v15 allowlist semantics (v16: gentle — the app arm now decides hiding
/// instead of termination): while the shield runs in allowlist mode, regular
/// user apps not on the list are hidden and browser tabs on unlisted hosts
/// are intervened on. Each arm guards independently against an empty list —
/// an empty allowlist blocks nothing (instead of everything).
public enum AllowlistRules {
    /// Always implicitly allowed, so the machine stays operable: the Timer
    /// itself, Finder, and System Settings.
    public static let essentialBundleIDs: Set<String> = [
        "com.moritzthelen.timer",
        "com.apple.finder",
        "com.apple.systempreferences",
    ]

    /// The set that survives an allowlist, given what the user allowed.
    ///
    /// Allowing a *website* has to imply allowing something to open it in:
    /// otherwise the browser is hidden as an unlisted app and the website
    /// list can never do anything (user: "ich gebe eine Webseite ein, aber
    /// Chrome ist nicht erlaubt — dann sollte Chrome doch offen bleiben"). It
    /// is no hole either: the tab arm restricts every supported browser to
    /// the allowed hosts, so a browser that stays reachable is still only
    /// good for the sites on the list. With no allowed website at all, the
    /// browsers stay blocked like any other app.
    public static func essentials(
        withBrowsers browsers: Set<String>,
        allowedDomains: [String],
        base: Set<String> = essentialBundleIDs
    ) -> Set<String> {
        allowedDomains.isEmpty ? base : base.union(browsers)
    }

    /// True iff the app should be hidden: not allowed and not essential.
    /// Callers pre-filter to regular user apps — the activation policy is an
    /// AppKit concept the pure rule cannot see. With zero allowed apps the
    /// app arm never engages.
    /// `emptyListBlocksAll` decides what an empty allowed set means. The v15
    /// shield mode passes false: a half-configured allowlist must not lock the
    /// Mac down behind the user's back. The v24 emergency passes true —
    /// starting it is a deliberate act with a duration, so "nothing selected"
    /// means "nothing but the essentials" rather than "no block at all"
    /// (user report: an empty list made the emergency do nothing).
    public static func shouldHide(
        bundleID: String,
        allowed: Set<String>,
        essential: Set<String> = essentialBundleIDs,
        emptyListBlocksAll: Bool = false
    ) -> Bool {
        guard !allowed.isEmpty || emptyListBlocksAll else { return false }
        return !allowed.contains(bundleID) && !essential.contains(bundleID)
    }

    /// True iff the browser's current tab should be intervened on (v16:
    /// switched away from — closing remains only the Arc fallback): the host
    /// is present and matches no allowed domain (suffix semantics like the
    /// blocklist). Internal/blank pages (nil or empty host, e.g. new tabs)
    /// are never touched; with zero allowed domains the tab arm never
    /// engages.
    public static func shouldCloseTab(host: String?, allowedDomains: [String]) -> Bool {
        guard !allowedDomains.isEmpty, let host, !host.isEmpty else { return false }
        return !allowedDomains.contains { FocusBlockRules.domainMatches(host: host, entry: $0) }
    }
}
