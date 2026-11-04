// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UsualUI",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "UsualUI", targets: ["UsualUI"])
    ],
    dependencies: [
        .package(path: "../HermesKit")
    ],
    targets: [
        .target(name: "UsualUI", dependencies: ["HermesKit"], resources: [.process("Resources")]),
        .testTarget(name: "UsualUITests", dependencies: ["UsualUI"]),
    ]
)
