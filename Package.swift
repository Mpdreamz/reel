// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Reel",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "reel", targets: ["reel"])],
    dependencies: [.package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.0")],
    targets: [
        // What a run says it is doing, as JSON lines: shared with whatever watches a run, the companion app.
        .target(name: "ReelEvents"),
        .target(name: "ReelCore", dependencies: ["ReelEvents"], resources: [.copy("Resources/Screen")]),
        .executableTarget(
            name: "reel",
            dependencies: ["ReelCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),
        .testTarget(name: "ReelCoreTests", dependencies: ["ReelCore"]),
        // The menu bar app that shows a run's progress (scripts/companion.sh bundles it as Reel Companion.app).
        .executableTarget(name: "ReelCompanion", dependencies: ["ReelEvents"]),
        .testTarget(name: "ReelEventsTests", dependencies: ["ReelEvents"]),
        // The app reels/fixture.reel records (scripts/fixture.sh bundles it): a ticking window and a tone.
        .executableTarget(name: "ReelFixture"),
    ]
)
