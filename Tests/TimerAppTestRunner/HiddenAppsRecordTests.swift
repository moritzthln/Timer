import Foundation
import TimerCore

func runHiddenAppsRecordTests() {
    test("starts empty and records added ids") {
        var record = HiddenAppsRecord()
        try expect(record.isEmpty, "fresh record is empty")
        record.add("com.hnc.Discord")
        record.add("com.spotify.client")
        try expect(!record.isEmpty, "record holds the added ids")
        try expectEqual(
            record.drain(), ["com.hnc.Discord", "com.spotify.client"],
            "drain returns everything recorded"
        )
    }

    test("adding the same id twice keeps one entry") {
        var record = HiddenAppsRecord()
        record.add("com.hnc.Discord")
        record.add("com.hnc.Discord")
        try expectEqual(record.drain(), ["com.hnc.Discord"], "idempotent add")
    }

    test("drain clears the record") {
        var record = HiddenAppsRecord()
        record.add("com.hnc.Discord")
        _ = record.drain()
        try expect(record.isEmpty, "drained record is empty")
        try expectEqual(record.drain(), [], "second drain returns nothing")
    }

    test("record is usable again after a drain") {
        var record = HiddenAppsRecord()
        record.add("com.hnc.Discord")
        _ = record.drain()
        record.add("com.spotify.client")
        try expectEqual(
            record.drain(), ["com.spotify.client"],
            "post-drain adds start a fresh record"
        )
    }
}
