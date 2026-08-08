import Foundation
import TimerCore

func runMenuBarPresentationTests() {
    test("idle shows icon only") {
        let p = MenuBarPresentation.make(phase: .idle, remainingSeconds: 1500)
        try expectEqual(p.symbol, "timer", "symbol")
        try expectEqual(p.title, "", "title")
    }

    test("running single shows time only") {
        let p = MenuBarPresentation.make(
            phase: .running(endDate: Date(), total: 1500, kind: .single),
            remainingSeconds: 1477
        )
        try expectNil(p.symbol, "no icon while running")
        try expectEqual(p.title, "24:37", "title")
    }

    test("running focus shows time only, break shows cup") {
        let focus = MenuBarPresentation.make(
            phase: .running(endDate: Date(), total: 1500, kind: .pomodoro(phase: .focus, round: 1)),
            remainingSeconds: 900
        )
        try expectNil(focus.symbol, "focus = time only")
        let brk = MenuBarPresentation.make(
            phase: .running(endDate: Date(), total: 300, kind: .pomodoro(phase: .shortBreak, round: 1)),
            remainingSeconds: 300
        )
        try expectEqual(brk.symbol, "cup.and.saucer.fill", "break icon")
        let long = MenuBarPresentation.make(
            phase: .running(endDate: Date(), total: 900, kind: .pomodoro(phase: .longBreak, round: 4)),
            remainingSeconds: 900
        )
        try expectEqual(long.symbol, "cup.and.saucer.fill", "long break icon")
    }

    test("paused shows pause icon plus time") {
        let p = MenuBarPresentation.make(
            phase: .paused(remaining: 1400, total: 1500, kind: .single),
            remainingSeconds: 1400
        )
        try expectEqual(p.symbol, "pause.fill", "symbol")
        try expectEqual(p.title, "23:20", "title")
    }

    test("finished shows zero time only") {
        let p = MenuBarPresentation.make(phase: .finished, remainingSeconds: 0)
        try expectNil(p.symbol, "no icon")
        try expectEqual(p.title, "0:00", "title")
    }

    test("compact format shows rounded-up whole minutes") {
        let running = MenuBarPresentation.make(
            phase: .running(endDate: Date(), total: 1500, kind: .single),
            remainingSeconds: 1477, format: .compact
        )
        try expectNil(running.symbol, "running single keeps time-only look")
        try expectEqual(running.title, "25m", "24:37 rounds up to 25m")
        let paused = MenuBarPresentation.make(
            phase: .paused(remaining: 1400, total: 1500, kind: .single),
            remainingSeconds: 1400, format: .compact
        )
        try expectEqual(paused.symbol, "pause.fill", "paused keeps its icon")
        try expectEqual(paused.title, "24m", "23:20 rounds up to 24m")
        let finished = MenuBarPresentation.make(
            phase: .finished, remainingSeconds: 0, format: .compact
        )
        try expectEqual(finished.title, "0m", "finished compact zero")
    }

    test("compact format spells hours beyond sixty minutes") {
        let p = MenuBarPresentation.make(
            phase: .running(endDate: Date(), total: 7200, kind: .single),
            remainingSeconds: 3900, format: .compact
        )
        try expectEqual(p.title, "1h 5m", "hour split")
    }

    test("icon-only hides every title and always provides a symbol") {
        let single = MenuBarPresentation.make(
            phase: .running(endDate: Date(), total: 1500, kind: .single),
            remainingSeconds: 1477, showTime: false
        )
        try expectEqual(single.symbol, "timer", "running single falls back to the timer symbol")
        try expectEqual(single.title, "", "no time text")
        let brk = MenuBarPresentation.make(
            phase: .running(endDate: Date(), total: 300, kind: .pomodoro(phase: .shortBreak, round: 1)),
            remainingSeconds: 300, showTime: false
        )
        try expectEqual(brk.symbol, "cup.and.saucer.fill", "break keeps the cup")
        try expectEqual(brk.title, "", "no time text")
        let paused = MenuBarPresentation.make(
            phase: .paused(remaining: 1400, total: 1500, kind: .single),
            remainingSeconds: 1400, showTime: false
        )
        try expectEqual(paused.symbol, "pause.fill", "paused keeps its icon")
        try expectEqual(paused.title, "", "no time text")
        let finished = MenuBarPresentation.make(
            phase: .finished, remainingSeconds: 0, showTime: false
        )
        try expectEqual(finished.symbol, "checkmark.circle", "finished stays distinguishable")
        try expectEqual(finished.title, "", "no time text")
        let idle = MenuBarPresentation.make(
            phase: .idle, remainingSeconds: 1500, showTime: false
        )
        try expectEqual(idle.symbol, "timer", "idle unchanged")
        try expectEqual(idle.title, "", "idle never had a title")
    }
}
