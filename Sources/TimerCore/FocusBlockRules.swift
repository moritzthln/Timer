import Foundation

public enum FocusBlockRules {
    /// Blocking runs only during running focus work: single timers and
    /// pomodoro focus phases. Breaks and pauses are free time.
    public static func isActive(phase: TimerEngine.Phase, enabled: Bool) -> Bool {
        guard enabled, case .running(_, _, let kind) = phase else { return false }
        switch kind {
        case .single:
            return true
        case .pomodoro(let pomPhase, _):
            return pomPhase == .focus
        }
    }

    /// True if `host` is the entry itself or a subdomain of it.
    public static func domainMatches(host: String, entry: String) -> Bool {
        let normalizedHost = host.lowercased()
        let normalizedEntry = entry.lowercased()
        return normalizedHost == normalizedEntry
            || normalizedHost.hasSuffix("." + normalizedEntry)
    }
}

extension FocusBlockRules {
    /// The host of a page that may be judged at all — nil for everything that
    /// is not a real website.
    ///
    /// Only http(s) URLs carry a blockable host. Browser-internal pages use
    /// their own schemes, and `URL.host` happily returns "newtab" for
    /// `chrome://newtab/` — which matched no allowlist entry and got new tabs
    /// blocked (user report, v22.1). about:blank and an empty address bar have
    /// no host either, so both are neutral by the same rule.
    public static func blockableHost(urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return host
    }
}
