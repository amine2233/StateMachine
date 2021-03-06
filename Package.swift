// swift-tools-version:4.1
import PackageDescription

let package = Package(
    name: "StateMachine",
    products: [
        .library(
            name: "StateMachine",
            targets: ["StateMachine"])
        ],
    targets: [
        .target(
            name: "StateMachine",
            dependencies: []
            ),
        .testTarget(
            name: "StateMachineTests",
            dependencies: ["StateMachine"])
        ]
)
