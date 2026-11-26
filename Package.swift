// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Liftoff",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LiftoffCore", resources: [.copy("Resources/voices.json")]),
        .target(name: "LiftoffSystem", dependencies: ["LiftoffCore"]),
        .executableTarget(name: "Liftoff", dependencies: ["LiftoffCore", "LiftoffSystem"]),
        .executableTarget(name: "liftoff-voices", dependencies: ["LiftoffCore", "LiftoffSystem"]),
        .testTarget(name: "LiftoffCoreTests", dependencies: ["LiftoffCore"]),
        .testTarget(name: "LiftoffSystemTests", dependencies: ["LiftoffSystem", "LiftoffCore"]),
    ]
)
