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

func runEmergencyAllowlistTests() {
    test("an empty emergency list hides everything but the essentials") {
        // v24.1: the shield mode must not lock down on a half-filled list…
        try expect(!AllowlistRules.shouldHide(
            bundleID: "com.hnc.Discord", allowed: [], emptyListBlocksAll: false
        ), "shield mode: empty list blocks nothing")
        // …while the emergency, started deliberately with a duration, treats
        // "nothing selected" as "nothing but the essentials".
        try expect(AllowlistRules.shouldHide(
            bundleID: "com.hnc.Discord", allowed: [], emptyListBlocksAll: true
        ), "emergency: empty list hides a normal app")
        try expect(!AllowlistRules.shouldHide(
            bundleID: "com.apple.finder", allowed: [], emptyListBlocksAll: true
        ), "essentials survive an empty emergency list")
        try expect(!AllowlistRules.shouldHide(
            bundleID: "com.apple.dt.Xcode", allowed: ["com.apple.dt.Xcode"],
            emptyListBlocksAll: true
        ), "a listed app stays reachable")
    }
}

func runAllowlistBrowserTests() {
    let browsers: Set<String> = ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser"]

    test("an allowed website keeps the browsers reachable") {
        // Otherwise the browser is hidden as an unlisted app and the website
        // list can never do anything at all.
        let essentials = AllowlistRules.essentials(
            withBrowsers: browsers, allowedDomains: ["wikipedia.org"]
        )
        try expect(!AllowlistRules.shouldHide(
            bundleID: "com.google.Chrome", allowed: ["notion.id"], essential: essentials
        ), "Chrome survives while a website is allowed")
        try expect(AllowlistRules.shouldHide(
            bundleID: "com.hnc.Discord", allowed: ["notion.id"], essential: essentials
        ), "everything else still goes")
    }

    test("without an allowed website the browsers are blocked like any app") {
        let essentials = AllowlistRules.essentials(withBrowsers: browsers, allowedDomains: [])
        try expect(AllowlistRules.shouldHide(
            bundleID: "com.google.Chrome", allowed: ["notion.id"], essential: essentials
        ), "no website allowed, no browser needed")
        try expect(!AllowlistRules.shouldHide(
            bundleID: "com.apple.finder", allowed: ["notion.id"], essential: essentials
        ), "the essentials are untouched by all this")
    }
}
