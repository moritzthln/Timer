import Foundation
import TimerCore

func runBlockAttemptTests() {
    test("a hidden, windowed app stops the loop") {
        let plan = BlockAttempt.plan(
            attempt: 0, hidden: true, fullscreen: false, frontmost: false,
            accessibilityGranted: true, keyEventAllowed: true
        )
        try expect(plan.stop, "hidden and windowed is the goal state")
        try expect(plan.isEmpty, "nothing left to do")
    }

    test("a hidden app with a surviving fullscreen window is unhidden first") {
        // The trap the user kept hitting: hide() succeeds on a fullscreen app
        // but leaves the window on its Space, and a hidden app exposes no AX
        // windows — so nothing could ever un-fullscreen it again.
        let plan = BlockAttempt.plan(
            attempt: 0, hidden: true, fullscreen: true, frontmost: false,
            accessibilityGranted: true, keyEventAllowed: true
        )
        try expect(plan.unhide, "bring it back so its windows exist again")
        try expect(!plan.stop && !plan.hide, "and do not hide it straight back")
    }

    test("a fullscreen app is never hidden on the way") {
        for attempt in [0, 3, 9, 29] {
            let plan = BlockAttempt.plan(
                attempt: attempt, hidden: false, fullscreen: true, frontmost: true,
                accessibilityGranted: true, keyEventAllowed: true
            )
            try expect(!plan.hide, "attempt \(attempt) would leave the Space behind")
            try expect(!plan.minimize, "minimising a fullscreen window does nothing")
        }
    }

    test("a windowed app is hidden, and minimised once it resists") {
        let first = BlockAttempt.plan(
            attempt: 0, hidden: false, fullscreen: false, frontmost: false,
            accessibilityGranted: true, keyEventAllowed: true
        )
        try expect(first.hide, "hide is the gentle route")
        try expect(!first.minimize, "minimising is a fallback, not an opener")
        let later = BlockAttempt.plan(
            attempt: BlockAttempt.minimizeFrom, hidden: false, fullscreen: false,
            frontmost: false, accessibilityGranted: true, keyEventAllowed: true
        )
        try expect(later.minimize, "an app that keeps refusing gets minimised")
    }

    test("keyboard shortcuts go to the frontmost app only") {
        let background = BlockAttempt.plan(
            attempt: 0, hidden: false, fullscreen: true, frontmost: false,
            accessibilityGranted: true, keyEventAllowed: true
        )
        try expect(!background.sendExitFullscreenKey, "key events would land in the wrong app")
        try expect(background.exitFullscreenViaAX, "the AX write reaches it regardless")
        let front = BlockAttempt.plan(
            attempt: 0, hidden: false, fullscreen: true, frontmost: true,
            accessibilityGranted: true, keyEventAllowed: true
        )
        try expect(front.sendExitFullscreenKey, "a frontmost fullscreen app gets the shortcut")
    }

    test("the toggle shortcuts never fire against a windowed app") {
        // They are toggles: sending one to an app that is not in fullscreen
        // puts it *into* fullscreen.
        for attempt in [0, 4, 10, 29] {
            let plan = BlockAttempt.plan(
                attempt: attempt, hidden: false, fullscreen: false, frontmost: true,
                accessibilityGranted: true, keyEventAllowed: true
            )
            try expect(!plan.sendExitFullscreenKey, "attempt \(attempt) must not toggle fullscreen on")
            try expect(!plan.sendSpaceLeftKey, "attempt \(attempt) has no Space to leave")
        }
    }

    test("the throttle suppresses only the keyboard") {
        let plan = BlockAttempt.plan(
            attempt: 3, hidden: false, fullscreen: true, frontmost: true,
            accessibilityGranted: true, keyEventAllowed: false
        )
        try expect(!plan.sendExitFullscreenKey && !plan.sendSpaceLeftKey, "not during the animation")
        try expect(plan.exitFullscreenViaAX, "the idempotent route keeps going")
    }

    test("a stubborn background app is pulled forward late, and only once") {
        let early = BlockAttempt.plan(
            attempt: BlockAttempt.activateFrom - 1, hidden: false, fullscreen: true,
            frontmost: false, accessibilityGranted: true, keyEventAllowed: true,
            escortAllowed: true
        )
        try expect(!early.activate, "the invisible routes get their chance first")
        let late = BlockAttempt.plan(
            attempt: BlockAttempt.activateFrom, hidden: false, fullscreen: true,
            frontmost: false, accessibilityGranted: true, keyEventAllowed: true,
            escortAllowed: true
        )
        try expect(late.activate, "AX has failed long enough — the shortcut needs the app in front")
        let blocked = BlockAttempt.plan(
            attempt: BlockAttempt.activateFrom, hidden: false, fullscreen: true,
            frontmost: false, accessibilityGranted: true, keyEventAllowed: true,
            escortAllowed: false
        )
        try expect(!blocked.activate, "one app at a time, or the user is thrown across Spaces")
    }

    test("without Accessibility a background fullscreen app is at least hidden") {
        let plan = BlockAttempt.plan(
            attempt: 0, hidden: false, fullscreen: true, frontmost: false,
            accessibilityGranted: false, keyEventAllowed: true
        )
        try expect(!plan.exitFullscreenViaAX, "no permission, no AX write")
        try expect(plan.hide, "out of the way beats staying on screen")
    }

    test("the Space shortcut is the last technique to join") {
        let before = BlockAttempt.plan(
            attempt: BlockAttempt.spaceLeftFrom - 1, hidden: false, fullscreen: true,
            frontmost: true, accessibilityGranted: true, keyEventAllowed: true
        )
        try expect(!before.sendSpaceLeftKey, "not while the exit shortcut still has a chance")
        let after = BlockAttempt.plan(
            attempt: BlockAttempt.spaceLeftFrom, hidden: false, fullscreen: true,
            frontmost: true, accessibilityGranted: true, keyEventAllowed: true
        )
        try expect(after.sendSpaceLeftKey, "for apps that ignore the exit shortcut entirely")
    }
}
