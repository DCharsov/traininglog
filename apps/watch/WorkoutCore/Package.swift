// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorkoutCore",
    platforms: [.macOS(.v13), .watchOS(.v10)],
    products: [.library(name: "WorkoutCore", targets: ["WorkoutCore"])],
    targets: [
        .target(name: "WorkoutCore", resources: [.process("Resources")]),
        .testTarget(name: "WorkoutCoreTests", dependencies: ["WorkoutCore"])
    ]
)
