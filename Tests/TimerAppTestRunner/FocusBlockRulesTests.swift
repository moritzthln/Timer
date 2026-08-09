import Foundation
import TimerCore

func runFocusBlockRulesTests() {
    test("block is active only while running a focus-kind session with the toggle on") {
        let end = Date(timeIntervalSince1970: 2_000_000)
        try expect(FocusBlockRules.isActive(
            phase: .running(endDate: end, total: 60, kind: .single), enabled: true
        ), "single running")
        try expect(FocusBlockRules.isActive(
            phase: .running(endDate: end, total: 60, kind: .pomodoro(phase: .focus, round: 1)), enabled: true
        ), "pomodoro focus")
        try expect(!FocusBlockRules.isActive(
            phase: .running(endDate: end, total: 60, kind: .pomodoro(phase: .shortBreak, round: 1)), enabled: true
        ), "break never blocks")
        try expect(!FocusBlockRules.isActive(
            phase: .running(endDate: end, total: 60, kind: .pomodoro(phase: .longBreak, round: 4)), enabled: true
        ), "long break never blocks")
        try expect(!FocusBlockRules.isActive(
            phase: .paused(remaining: 60, total: 60, kind: .single), enabled: true
        ), "paused never blocks")
        try expect(!FocusBlockRules.isActive(phase: .idle, enabled: true), "idle")
        try expect(!FocusBlockRules.isActive(phase: .finished, enabled: true), "finished")
        try expect(!FocusBlockRules.isActive(
            phase: .running(endDate: end, total: 60, kind: .single), enabled: false
        ), "toggle off wins")
    }

    test("domain matching covers exact and subdomains only") {
        try expect(FocusBlockRules.domainMatches(host: "youtube.com", entry: "youtube.com"), "exact")
        try expect(FocusBlockRules.domainMatches(host: "www.youtube.com", entry: "youtube.com"), "www")
        try expect(FocusBlockRules.domainMatches(host: "m.youtube.com", entry: "youtube.com"), "subdomain")
        try expect(!FocusBlockRules.domainMatches(host: "notyoutube.com", entry: "youtube.com"), "suffix trap")
        try expect(!FocusBlockRules.domainMatches(host: "youtube.com.evil.net", entry: "youtube.com"), "middle trap")
        try expect(FocusBlockRules.domainMatches(host: "WWW.YouTube.com", entry: "youtube.com"), "case-insensitive")
    }
}

func runDndRulesTests() {
    test("dnd stays on while paused, unlike the focus block") {
        let end = Date(timeIntervalSince1970: 2_000_000)
        try expect(DndRules.isActive(
            phase: .running(endDate: end, total: 60, kind: .single), enabled: true
        ), "running single")
        try expect(DndRules.isActive(
            phase: .paused(remaining: 30, total: 60, kind: .single), enabled: true
        ), "paused single stays on")
        try expect(DndRules.isActive(
            phase: .paused(remaining: 30, total: 60, kind: .pomodoro(phase: .focus, round: 2)), enabled: true
        ), "paused pomodoro focus stays on")
        try expect(!DndRules.isActive(
            phase: .running(endDate: end, total: 60, kind: .pomodoro(phase: .shortBreak, round: 1)), enabled: true
        ), "pomodoro break stays off")
        try expect(!DndRules.isActive(
            phase: .paused(remaining: 30, total: 60, kind: .pomodoro(phase: .longBreak, round: 4)), enabled: true
        ), "paused during a break stays off")
        try expect(!DndRules.isActive(phase: .idle, enabled: true), "idle off")
        try expect(!DndRules.isActive(phase: .finished, enabled: true), "finished off")
        try expect(!DndRules.isActive(
            phase: .paused(remaining: 30, total: 60, kind: .single), enabled: false
        ), "toggle off wins")
    }
}

func runBlockableHostTests() {
    test("only real web pages carry a blockable host") {
        try expectEqual(FocusBlockRules.blockableHost(urlString: "https://www.google.com/search?q=x"), "www.google.com", "https")
        try expectEqual(FocusBlockRules.blockableHost(urlString: "http://example.com"), "example.com", "http")
        try expectNil(FocusBlockRules.blockableHost(urlString: "chrome://newtab/"), "chrome new tab is neutral")
        try expectNil(FocusBlockRules.blockableHost(urlString: "chrome://new-tab-page/"), "chrome new-tab-page is neutral")
        try expectNil(FocusBlockRules.blockableHost(urlString: "about:blank"), "blank page is neutral")
        try expectNil(FocusBlockRules.blockableHost(urlString: "arc://newtab"), "arc new tab is neutral")
        try expectNil(FocusBlockRules.blockableHost(urlString: "safari-resource://start"), "safari start page is neutral")
        try expectNil(FocusBlockRules.blockableHost(urlString: ""), "empty address bar")
        try expectNil(FocusBlockRules.blockableHost(urlString: nil), "no url at all")
    }
}
