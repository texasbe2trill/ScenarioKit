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
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "ScenarioKit",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "ScenarioKitTests",
            dependencies: ["ScenarioKit"]
        ),
    ]
)