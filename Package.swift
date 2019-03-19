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
            dependencies: [],
            path: "Sources"
            ),
        .testTarget(
            name: "StateMachineTests",
            dependencies: ["StateMachine"],
            path: "Tests")
        ]
)
