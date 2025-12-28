// swift-tools-version: 6.0
import PackageDescription

let package: Package = Package(
    name: "ScenarioKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "scenariokit",
            targets: ["ScenarioKit"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "ScenarioKit"
        ),
        .testTarget(
            name: "ScenarioKitTests",
            dependencies: ["ScenarioKit"]
        ),
    ]
)