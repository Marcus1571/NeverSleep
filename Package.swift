// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NeverSleep",
    platforms: [.macOS(.v11)],
    targets: [
        .executableTarget(
            name: "NeverSleep",
            dependencies: ["NeverSleepCore"],
            path: "Sources/NeverSleep",
            resources: []
        ),
        .executableTarget(
            name: "neversleepctl",
            dependencies: ["NeverSleepCore"],
            path: "Sources/neversleepctl"
        ),
        .target(name: "NeverSleepCore", path: "Sources/NeverSleepCore"),
    ]
)
