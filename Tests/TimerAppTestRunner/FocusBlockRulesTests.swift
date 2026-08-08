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
