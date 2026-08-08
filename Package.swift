// swift-tools-version:5.9
import PackageDescription

// Note: no XCTest target — the machine builds with Command Line Tools only,
// which ship no XCTest.framework. Tests run via the TimerAppTestRunner
// executable instead: `swift run TimerAppTestRunner`.
let package = Package(
    name: "TimerApp",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "TimerCore", path: "Sources/TimerCore"),
        .executableTarget(
            name: "TimerApp",
            dependencies: ["TimerCore"],
            path: "Sources/TimerApp"
        ),
        .executableTarget(
            name: "TimerAppTestRunner",
            dependencies: ["TimerCore"],
            path: "Tests/TimerAppTestRunner"
        ),
    ]
)
