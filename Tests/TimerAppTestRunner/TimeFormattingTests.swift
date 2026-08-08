import TimerCore

func runTimeFormattingTests() {
    test("formats below one hour as m:ss") {
        try expectEqual(TimeFormatting.format(seconds: 0), "0:00")
        try expectEqual(TimeFormatting.format(seconds: 59), "0:59")
        try expectEqual(TimeFormatting.format(seconds: 60), "1:00")
        try expectEqual(TimeFormatting.format(seconds: 1477), "24:37")
        try expectEqual(TimeFormatting.format(seconds: 3599), "59:59")
    }

    test("formats at or above one hour with hours") {
        try expectEqual(TimeFormatting.format(seconds: 3600), "1:00:00")
        try expectEqual(TimeFormatting.format(seconds: 3900), "1:05:00")
        try expectEqual(TimeFormatting.format(seconds: 43_200), "12:00:00")
    }

    test("clamps negative to zero") {
        try expectEqual(TimeFormatting.format(seconds: -5), "0:00")
    }
}
