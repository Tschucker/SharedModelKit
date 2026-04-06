// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SharedModelKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "SharedModelKit", targets: ["SharedModelKit"]),
    ],
    targets: [
        .target(
            name: "SharedModelKit",
            path: "Sources/SharedModelKit"
        ),
        .testTarget(
            name: "SharedModelKitTests",
            dependencies: ["SharedModelKit"],
            path: "Tests/SharedModelKitTests"
        ),
    ]
)
