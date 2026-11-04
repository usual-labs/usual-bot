// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HermesKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "HermesKit", targets: ["HermesKit"])
    ],
    targets: [
        .target(name: "HermesKit"),
        .testTarget(name: "HermesKitTests", dependencies: ["HermesKit"], resources: [.copy("Fixtures")]),
    ]
)
