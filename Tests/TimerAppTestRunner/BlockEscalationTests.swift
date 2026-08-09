import Foundation
import TimerCore

func runBlockEscalationTests() {
    test("nothing tried yet on a visible app starts with hide") {
        try expectEqual(
            BlockEscalation.next(step: .start, appVisible: true, accessibilityGranted: false),
            .hide, "step 1 is always the gentle hide"
        )
        try expectEqual(
            BlockEscalation.next(step: .start, appVisible: true, accessibilityGranted: true),
            .hide, "the permission does not skip step 1"
        )
    }

    test("an already invisible app needs no intervention") {
        try expectEqual(
            BlockEscalation.next(step: .start, appVisible: false, accessibilityGranted: true),
            .done, "an app the user hid himself is left alone"
        )
    }

    test("hidden after step 1 is done") {
        try expectEqual(
            BlockEscalation.next(step: .hideTried, appVisible: false, accessibilityGranted: false),
            .done, "the gentle hide worked"
        )
    }

    test("still visible after step 1 escalates to un-fullscreen with permission") {
        try expectEqual(
            BlockEscalation.next(step: .hideTried, appVisible: true, accessibilityGranted: true),
            .unfullscreenThenHide, "fullscreen apps ignore hide(); pull them out first"
        )
    }

    test("still visible after step 1 goes straight to the overlay without permission") {
        try expectEqual(
            BlockEscalation.next(step: .hideTried, appVisible: true, accessibilityGranted: false),
            .overlay, "no Accessibility permission means step 2 is skipped"
        )
    }

    test("hidden after step 2 is done") {
        try expectEqual(
            BlockEscalation.next(
                step: .unfullscreenTried, appVisible: false, accessibilityGranted: true
            ),
            .done, "leaving fullscreen let the hide land"
        )
    }

    test("still visible after step 2 falls through to the overlay") {
        try expectEqual(
            BlockEscalation.next(
                step: .unfullscreenTried, appVisible: true, accessibilityGranted: true
            ),
            .overlay, "last resort: cover the app"
        )
        try expectEqual(
            BlockEscalation.next(
                step: .unfullscreenTried, appVisible: true, accessibilityGranted: false
            ),
            .overlay, "the permission state no longer matters at this point"
        )
    }

    test("a shown overlay stays while the app is visible") {
        try expectEqual(
            BlockEscalation.next(step: .overlayShown, appVisible: true, accessibilityGranted: false),
            .overlay, "the ladder never escalates past the overlay"
        )
        try expectEqual(
            BlockEscalation.next(step: .overlayShown, appVisible: true, accessibilityGranted: true),
            .overlay, "granting the permission mid-cover does not re-run step 2"
        )
    }

    test("the overlay comes down once the app is gone") {
        try expectEqual(
            BlockEscalation.next(step: .overlayShown, appVisible: false, accessibilityGranted: true),
            .done, "nothing left to cover"
        )
    }

    test("every step is reachable in one ladder run") {
        var step = BlockEscalation.Step.start
        var actions: [BlockEscalation.Action] = []
        // Worst case: an app that stays visible through both hide attempts.
        for _ in 0..<4 {
            let action = BlockEscalation.next(
                step: step, appVisible: true, accessibilityGranted: true
            )
            actions.append(action)
            step = BlockEscalation.Step.after(action)
        }
        try expectEqual(
            actions, [.hide, .unfullscreenThenHide, .overlay, .overlay],
            "hide → un-fullscreen+hide → overlay → stay"
        )
    }

    test("the step after an action is the ladder's memory") {
        try expectEqual(BlockEscalation.Step.after(.hide), .hideTried, "")
        try expectEqual(
            BlockEscalation.Step.after(.unfullscreenThenHide), .unfullscreenTried, ""
        )
        try expectEqual(BlockEscalation.Step.after(.overlay), .overlayShown, "")
        try expectEqual(BlockEscalation.Step.after(.done), .start, "a finished ladder rearms")
    }
}
