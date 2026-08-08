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

    test("wording formats hours and minutes for stats") {
        try expectEqual(TimeFormatting.wording(seconds: 0), "0 min")
        try expectEqual(TimeFormatting.wording(seconds: 2700), "45 min")
        try expectEqual(TimeFormatting.wording(seconds: 5100), "1 h 25 min")
        try expectEqual(TimeFormatting.wording(seconds: 7200), "2 h 0 min")
        try expectEqual(TimeFormatting.wording(seconds: 59), "0 min")
    }

    test("compact rounds whole minutes up and spells hours") {
        try expectEqual(TimeFormatting.compact(seconds: 0), "0m")
        try expectEqual(TimeFormatting.compact(seconds: 1), "1m")
        try expectEqual(TimeFormatting.compact(seconds: 60), "1m")
        try expectEqual(TimeFormatting.compact(seconds: 61), "2m")
        try expectEqual(TimeFormatting.compact(seconds: 1477), "25m")
        try expectEqual(TimeFormatting.compact(seconds: 3599), "60m")
        try expectEqual(TimeFormatting.compact(seconds: 3600), "1h 0m")
        try expectEqual(TimeFormatting.compact(seconds: 3900), "1h 5m")
        try expectEqual(TimeFormatting.compact(seconds: -5), "0m")
    }
}
