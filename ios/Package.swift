// swift-tools-version: 5.9
import PackageDescription

let package = Package(name: "RepbookCore", platforms: [.macOS(.v13)], products: [.library(name: "RepbookCore", targets: ["RepbookCore"])], targets: [
    .target(name: "RepbookCore", path: "Shared", exclude: ["WorkoutActivity.swift"]),
    .testTarget(name: "RepbookCoreTests", dependencies: ["RepbookCore"], path: "Tests")
])
