import TimerCore

func runPomodoroConfigTests() {
    let config = PomodoroConfig(focusMinutes: 25, breakMinutes: 5, longBreakMinutes: 15, rounds: 4)

    test("durations map phases to seconds") {
        try expectEqual(config.duration(of: .focus), 1500, "focus")
        try expectEqual(config.duration(of: .shortBreak), 300, "short break")
        try expectEqual(config.duration(of: .longBreak), 900, "long break")
    }

    test("focus advances to short break before the final round") {
        try expectEqual(
            config.next(after: .pomodoro(phase: .focus, round: 2)),
            .pomodoro(phase: .shortBreak, round: 2), "round 2"
        )
    }

    test("final-round focus advances to long break") {
        try expectEqual(
            config.next(after: .pomodoro(phase: .focus, round: 4)),
            .pomodoro(phase: .longBreak, round: 4), "round 4"
        )
    }

    test("short break advances to next-round focus") {
        try expectEqual(
            config.next(after: .pomodoro(phase: .shortBreak, round: 2)),
            .pomodoro(phase: .focus, round: 3), "increments round"
        )
    }

    test("long break restarts at round 1") {
        try expectEqual(
            config.next(after: .pomodoro(phase: .longBreak, round: 4)),
            .pomodoro(phase: .focus, round: 1), "cycle reset"
        )
    }
}
