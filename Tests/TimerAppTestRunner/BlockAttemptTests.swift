import Foundation
import TimerCore

func runBlockAttemptTests() {
    test("a hidden, windowed app stops the loop") {
        let plan = BlockAttempt.plan(
            attempt: 0, hidden: true, occupiesScreen: false, accessibilityGranted: true
        )
        try expect(plan.stop, "hidden and windowed is the goal state")
        try expect(plan.isEmpty, "nothing left to do")
    }

    test("a hidden app that still holds a screen is unhidden first") {
        // The trap: hide() succeeds on a fullscreen app but leaves its Space
        // and window behind, and a hidden app exposes no AX windows — so
        // nothing could ever take it out of fullscreen again.
        let plan = BlockAttempt.plan(
            attempt: 0, hidden: true, occupiesScreen: true, accessibilityGranted: true
        )
        try expect(plan.unhide, "bring it back so its windows exist again")
        try expect(!plan.stop && !plan.hide, "and do not hide it straight back")
    }

    test("a screen-filling app goes to the sweep, never to hide") {
        for attempt in [0, 5, 29] {
            let plan = BlockAttempt.plan(
                attempt: attempt, hidden: false, occupiesScreen: true, accessibilityGranted: true
            )
            try expect(plan.sweepFullscreen, "attempt \(attempt) hands it to phase one")
            try expect(!plan.hide, "hiding it now would strand its Space")
            try expect(!plan.minimize, "minimising a fullscreen window does nothing")
        }
    }

    test("a windowed app is hidden, and minimised once it resists") {
        let first = BlockAttempt.plan(
            attempt: 0, hidden: false, occupiesScreen: false, accessibilityGranted: true
        )
        try expect(first.hide, "hide is the gentle route")
        try expect(!first.minimize, "minimising is a fallback, not an opener")
        let later = BlockAttempt.plan(
            attempt: BlockAttempt.minimizeFrom, hidden: false, occupiesScreen: false,
            accessibilityGranted: true
        )
        try expect(later.minimize, "an app that keeps refusing gets minimised")
    }

    test("without Accessibility only the hide remains") {
        let plan = BlockAttempt.plan(
            attempt: 9, hidden: false, occupiesScreen: false, accessibilityGranted: false
        )
        try expect(plan.hide, "hide needs no permission")
        try expect(!plan.minimize, "minimising does")
    }
}
