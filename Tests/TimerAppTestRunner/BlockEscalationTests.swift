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
        try expectEqual(BlockEscalation.Step.after(.spaceEscape), .escapeTried, "")
        try expectEqual(BlockEscalation.Step.after(.overlay), .overlayShown, "")
        try expectEqual(BlockEscalation.Step.after(.done), .start, "a finished ladder rearms")
    }

    // MARK: - v21 Space escape
    //
    // The rows above call the v18 signature, i.e. both escape inputs default
    // to false — they keep documenting the ladder for an app that is not in
    // front (or whose escape is throttled), which is exactly the old
    // behaviour. The rows below are the ones that reach the new rung.

    test("a still-frontmost app after step 1 escapes its Space") {
        try expectEqual(
            BlockEscalation.next(
                step: .hideTried, appVisible: true, appFrontmost: true,
                accessibilityGranted: false, escapeAllowed: true
            ),
            .spaceEscape, "without Accessibility the escape is the only working rung"
        )
    }

    test("the Accessibility rung stays preferred over the escape") {
        try expectEqual(
            BlockEscalation.next(
                step: .hideTried, appVisible: true, appFrontmost: true,
                accessibilityGranted: true, escapeAllowed: true
            ),
            .unfullscreenThenHide, "leaving fullscreen in place is the cleanest fix"
        )
    }

    test("a failed un-fullscreen escapes regardless of the reason") {
        try expectEqual(
            BlockEscalation.next(
                step: .unfullscreenTried, appVisible: true, appFrontmost: true,
                accessibilityGranted: true, escapeAllowed: true
            ),
            .spaceEscape, "Catalyst/Electron windows reject AXFullScreen — escape anyway"
        )
    }

    test("an app that is no longer in front is not worth a Space switch") {
        try expectEqual(
            BlockEscalation.next(
                step: .hideTried, appVisible: true, appFrontmost: false,
                accessibilityGranted: false, escapeAllowed: true
            ),
            .overlay, "the user already left the app on his own"
        )
        try expectEqual(
            BlockEscalation.next(
                step: .unfullscreenTried, appVisible: true, appFrontmost: false,
                accessibilityGranted: true, escapeAllowed: true
            ),
            .overlay, "same after step 2"
        )
    }

    test("a throttled escape falls back to the overlay") {
        try expectEqual(
            BlockEscalation.next(
                step: .hideTried, appVisible: true, appFrontmost: true,
                accessibilityGranted: false, escapeAllowed: false
            ),
            .overlay, "one escape per app per 3 s — the cover fills the gap"
        )
        try expectEqual(
            BlockEscalation.next(
                step: .unfullscreenTried, appVisible: true, appFrontmost: true,
                accessibilityGranted: true, escapeAllowed: false
            ),
            .overlay, "the throttle also holds after step 2"
        )
    }

    test("after the escape the ladder retries the hide") {
        try expectEqual(
            BlockEscalation.next(
                step: .escapeTried, appVisible: true, appFrontmost: false,
                accessibilityGranted: true, escapeAllowed: true
            ),
            .hide, "out of fullscreen focus, hide() usually lands now"
        )
        try expectEqual(
            BlockEscalation.next(
                step: .escapeTried, appVisible: true, appFrontmost: true,
                accessibilityGranted: false, escapeAllowed: true
            ),
            .hide, "even when the switch did not take, hiding comes before another escape"
        )
    }

    test("a hide that landed after the escape ends the ladder") {
        try expectEqual(
            BlockEscalation.next(
                step: .escapeTried, appVisible: false, appFrontmost: false,
                accessibilityGranted: true, escapeAllowed: true
            ),
            .done, "the Space switch made the hide work"
        )
    }

    test("the relentless run escapes once and then settles on the cover") {
        var step = BlockEscalation.Step.start
        var actions: [BlockEscalation.Action] = []
        var escaped = false
        // Worst case: a fullscreen app that survives every hide and rejects
        // AXFullScreen, with the 3 s throttle blocking the second escape.
        for _ in 0..<7 {
            let action = BlockEscalation.next(
                step: step, appVisible: true, appFrontmost: true,
                accessibilityGranted: true, escapeAllowed: !escaped
            )
            if action == .spaceEscape { escaped = true }
            actions.append(action)
            step = BlockEscalation.Step.after(action)
        }
        try expectEqual(
            actions,
            [
                .hide, .unfullscreenThenHide, .spaceEscape, .hide,
                .unfullscreenThenHide, .overlay, .overlay,
            ],
            "hide → un-fullscreen → escape → retry hide → un-fullscreen → cover"
        )
    }
}
