// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "StateMachine",
    platforms: [
        .macOS(.v10_15), .iOS(.v14), .tvOS(.v14), .watchOS(.v7), .visionOS(.v1)
    ],
    products: [
        .library(
            name: "StateMachine",
            targets: ["StateMachine"]
        )
    ],
    targets: [
        .target(
            name: "StateMachine",
            dependencies: []
        ),
        .testTarget(
            name: "StateMachineTests",
            dependencies: ["StateMachine"]
        )
    ]
)
