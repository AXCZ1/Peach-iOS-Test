// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PeachTestCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PeachTestCore", targets: ["PeachTestCore"])
    ],
    targets: [
        .target(
            name: "PeachTestCore",
            path: "PeachTest/Core",
            exclude: ["PeachSession.swift"]
        ),
        .testTarget(
            name: "PeachTestCoreTests",
            dependencies: ["PeachTestCore"],
            path: "PeachTestTests"
        )
    ]
)
