import Foundation
import TimerCore

func runBlockAttemptTests() {
    test("an invisible app stops the loop") {
        let plan = BlockAttempt.plan(
            attempt: 0, visible: false, frontmost: true, fullscreen: true,
            accessibilityGranted: true, keyEventAllowed: true
        )
        try expect(plan.stop, "gone means stop")
        try expect(plan.isEmpty, "and nothing is attempted on a gone app")
    }

    test("the first attempt hides and, with the permission, un-fullscreens") {
        let plan = BlockAttempt.plan(
            attempt: 0, visible: true, frontmost: false, fullscreen: false,
            accessibilityGranted: true, keyEventAllowed: true
        )
        try expect(plan.hide, "hide is always attempted")
        try expect(plan.exitFullscreenViaAX, "the AX write is idempotent, so it runs from the start")
        try expect(!plan.minimize, "minimising is a fallback, not an opener")
    }

    test("without Accessibility only the hide remains") {
        let plan = BlockAttempt.plan(
            attempt: 5, visible: true, frontmost: false, fullscreen: true,
            accessibilityGranted: false, keyEventAllowed: true
        )
        try expect(plan.hide, "hide needs no permission")
        try expect(!plan.exitFullscreenViaAX && !plan.minimize, "both AX routes stay off")
        try expect(!plan.sendExitFullscreenKey, "a background app never gets key events")
    }

    test("keyboard shortcuts go to the frontmost app only") {
        let background = BlockAttempt.plan(
            attempt: 0, visible: true, frontmost: false, fullscreen: true,
            accessibilityGranted: true, keyEventAllowed: true
        )
        try expect(!background.sendExitFullscreenKey, "key events would land in the wrong app")
        let front = BlockAttempt.plan(
            attempt: 0, visible: true, frontmost: true, fullscreen: true,
            accessibilityGranted: true, keyEventAllowed: true
        )
        try expect(front.sendExitFullscreenKey, "a frontmost fullscreen app gets the shortcut")
    }

    test("the throttle suppresses only the keyboard, never the rest") {
        let plan = BlockAttempt.plan(
            attempt: 3, visible: true, frontmost: true, fullscreen: true,
            accessibilityGranted: true, keyEventAllowed: false
        )
        try expect(!plan.sendExitFullscreenKey && !plan.sendSpaceLeftKey, "no shortcut during the animation")
        try expect(plan.hide && plan.exitFullscreenViaAX && plan.minimize, "everything idempotent keeps going")
    }

    test("a stubborn frontmost app is treated as fullscreen eventually") {
        let early = BlockAttempt.plan(
            attempt: BlockAttempt.assumeFullscreenFrom - 1, visible: true, frontmost: true,
            fullscreen: false, accessibilityGranted: true, keyEventAllowed: true
        )
        try expect(!early.sendExitFullscreenKey, "a windowed app must not be toggled into fullscreen")
        let late = BlockAttempt.plan(
            attempt: BlockAttempt.assumeFullscreenFrom, visible: true, frontmost: true,
            fullscreen: false, accessibilityGranted: true, keyEventAllowed: true
        )
        try expect(late.sendExitFullscreenKey, "apps that report no fullscreen window still get the shortcut")
    }

    test("the Space shortcut is the last technique to join") {
        let before = BlockAttempt.plan(
            attempt: BlockAttempt.spaceLeftFrom - 1, visible: true, frontmost: true,
            fullscreen: true, accessibilityGranted: true, keyEventAllowed: true
        )
        try expect(!before.sendSpaceLeftKey, "not while the exit shortcut still has a chance")
        let after = BlockAttempt.plan(
            attempt: BlockAttempt.spaceLeftFrom, visible: true, frontmost: true,
            fullscreen: true, accessibilityGranted: true, keyEventAllowed: true
        )
        try expect(after.sendSpaceLeftKey, "for apps that ignore the exit shortcut entirely")
    }

    test("minimising joins from its own attempt on") {
        for attempt in 0..<BlockAttempt.minimizeFrom {
            let plan = BlockAttempt.plan(
                attempt: attempt, visible: true, frontmost: false, fullscreen: false,
                accessibilityGranted: true, keyEventAllowed: true
            )
            try expect(!plan.minimize, "attempt \(attempt) still trusts the hide")
        }
        let plan = BlockAttempt.plan(
            attempt: BlockAttempt.minimizeFrom, visible: true, frontmost: false,
            fullscreen: false, accessibilityGranted: true, keyEventAllowed: true
        )
        try expect(plan.minimize, "an app that keeps refusing gets minimised")
    }
}
