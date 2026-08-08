import Foundation
import TimerCore

func runAppCategoryTests() {
    test("explicit category wins over the blocklist") {
        let explicit: [String: AppCategory] = ["com.hnc.Discord": .productive]
        try expectEqual(
            AppCategory.resolve(
                bundleID: "com.hnc.Discord",
                explicit: explicit,
                blockedBundleIDs: ["com.hnc.Discord"]
            ),
            .productive, "explicit beats blocklist"
        )
    }

    test("blocklisted apps default to distracting") {
        try expectEqual(
            AppCategory.resolve(
                bundleID: "com.valvesoftware.steam",
                explicit: [:],
                blockedBundleIDs: ["com.valvesoftware.steam"]
            ),
            .distracting, "blocklist implies distracting"
        )
    }

    test("unknown apps are neutral") {
        try expectEqual(
            AppCategory.resolve(
                bundleID: "com.apple.dt.Xcode",
                explicit: [:],
                blockedBundleIDs: []
            ),
            .neutral, "unknown is neutral"
        )
    }
}
