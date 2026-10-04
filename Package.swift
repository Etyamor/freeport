// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreePort",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FreePort", targets: ["FreePort"]),
        .library(name: "FreePortKit", targets: ["FreePortKit"]),
    ],
    targets: [
        // Port discovery, Docker lookup and release logic. No UI, so it's testable.
        .target(name: "FreePortKit", path: "Sources/FreePortKit"),
        // The menu bar app: SwiftUI views and the status item.
        .executableTarget(name: "FreePort", dependencies: ["FreePortKit"], path: "Sources/FreePort"),
        .testTarget(name: "FreePortKitTests", dependencies: ["FreePortKit"], path: "Tests/FreePortKitTests"),
    ]
)
