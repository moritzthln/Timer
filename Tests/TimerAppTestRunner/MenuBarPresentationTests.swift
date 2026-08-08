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
}
