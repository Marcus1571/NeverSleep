// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NeverSleep",
    platforms: [.macOS(.v11)],
    dependencies: [
        // Software updater (SPUStandardUpdaterController in AppDelegate) —
        // same setup as diskled-plus; distribution parity (KB feature 8).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0"),
        // Global keyboard shortcut: the Preferences recorder field + the
        // system-wide toggle hotkey (0.12.0). sindresorhus/KeyboardShortcuts.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "NeverSleep",
            dependencies: [
                "NeverSleepCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/NeverSleep",
            resources: []
        ),
        .executableTarget(
            name: "neversleep-helper",
            path: "Sources/neversleep-helper"
        ),
        .executableTarget(
            name: "neversleepctl",
            dependencies: ["NeverSleepCore"],
            path: "Sources/neversleepctl"
        ),
        .target(name: "NeverSleepCore", path: "Sources/NeverSleepCore"),
    ]
)
