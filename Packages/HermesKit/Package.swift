// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HermesKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "HermesKit", targets: ["HermesKit"])
    ],
    targets: [
        .target(name: "HermesKit"),
        .testTarget(name: "HermesKitTests", dependencies: ["HermesKit"], resources: [.copy("Fixtures")]),
    ]
)
