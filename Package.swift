// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StateMachine",
    platforms: [
        .macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)
    ],
    products: [
        .library(
            name: "StateMachine",
            targets: ["StateMachine"])
    ],
    targets: [
        .target(
            name: "StateMachine",
            dependencies: [],
            swiftSettings: [.swiftLanguageVersion(.v6)]
        ),
        .testTarget(
            name: "StateMachineTests",
            dependencies: ["StateMachine"])
    ]
)
