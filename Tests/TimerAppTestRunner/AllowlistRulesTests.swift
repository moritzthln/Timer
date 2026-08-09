import Foundation
import TimerCore

func runAllowlistRulesTests() {
    let allowed: Set<String> = ["com.apple.dt.Xcode", "com.apple.Safari"]

    test("essential apps are never hidden") {
        for id in ["com.moritzthelen.timer", "com.apple.finder", "com.apple.systempreferences"] {
            try expect(
                AllowlistRules.essentialBundleIDs.contains(id),
                "\(id) belongs to the essential set"
            )
            try expect(
                !AllowlistRules.shouldHide(bundleID: id, allowed: allowed),
                "\(id) survives even when unlisted"
            )
        }
    }

    test("allowed apps survive, unlisted regular apps hide") {
        try expect(
            !AllowlistRules.shouldHide(bundleID: "com.apple.dt.Xcode", allowed: allowed),
            "allowed app survives"
        )
        try expect(
            AllowlistRules.shouldHide(bundleID: "com.hnc.Discord", allowed: allowed),
            "unlisted regular app hides"
        )
    }

    test("custom essential set overrides the default") {
        try expect(
            !AllowlistRules.shouldHide(
                bundleID: "com.example.helper", allowed: allowed, essential: ["com.example.helper"]
            ),
            "custom essential survives"
        )
        try expect(
            AllowlistRules.shouldHide(
                bundleID: "com.apple.finder", allowed: allowed, essential: []
            ),
            "empty essential set protects nothing"
        )
    }

    test("empty allowed apps disengage the app arm") {
        try expect(
            !AllowlistRules.shouldHide(bundleID: "com.hnc.Discord", allowed: []),
            "zero allowed apps: the app arm never fires"
        )
    }

    test("tab closes only for a present unlisted host") {
        let domains = ["wikipedia.org", "github.com"]
        try expect(
            !AllowlistRules.shouldCloseTab(host: nil, allowedDomains: domains),
            "nil host (internal/new-tab page) never closes"
        )
        try expect(
            !AllowlistRules.shouldCloseTab(host: "", allowedDomains: domains),
            "empty host never closes"
        )
        try expect(
            AllowlistRules.shouldCloseTab(host: "youtube.com", allowedDomains: domains),
            "unlisted host closes"
        )
    }

    test("allowed domains cover exact host and subdomains only") {
        let domains = ["wikipedia.org"]
        try expect(
            !AllowlistRules.shouldCloseTab(host: "wikipedia.org", allowedDomains: domains),
            "exact match stays open"
        )
        try expect(
            !AllowlistRules.shouldCloseTab(host: "de.wikipedia.org", allowedDomains: domains),
            "subdomain stays open"
        )
        try expect(
            AllowlistRules.shouldCloseTab(host: "notwikipedia.org", allowedDomains: domains),
            "suffix trap closes"
        )
        try expect(
            AllowlistRules.shouldCloseTab(host: "wikipedia.org.evil.net", allowedDomains: domains),
            "middle trap closes"
        )
        try expect(
            !AllowlistRules.shouldCloseTab(host: "DE.Wikipedia.org", allowedDomains: domains),
            "case-insensitive match stays open"
        )
    }

    test("empty allowed domains disengage the tab arm") {
        try expect(
            !AllowlistRules.shouldCloseTab(host: "youtube.com", allowedDomains: []),
            "zero allowed domains: the tab arm never fires"
        )
    }
}
