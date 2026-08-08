func runSmokeTests() {
    test("harness runs") {
        try expect(true, "harness must execute test bodies")
    }
}
