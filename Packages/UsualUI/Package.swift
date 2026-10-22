// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsualUI",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "UsualUI", targets: ["UsualUI"])
    ],
    dependencies: [
        .package(path: "../HermesKit")
    ],
    targets: [
        .target(name: "UsualUI", dependencies: ["HermesKit"]),
        .testTarget(name: "UsualUITests", dependencies: ["UsualUI"]),
    ]
)
