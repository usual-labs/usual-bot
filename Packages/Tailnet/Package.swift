// swift-tools-version: 6.0
import PackageDescription

// TailscaleKit.xcframework is built from tailscale/libtailscale (`make ios-fat` in its swift/ folder)
// and isn't checked in. It has iPhone and Simulator slices only, so the Mac build skips it.
let package = Package(
    name: "Tailnet",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "Tailnet", targets: ["Tailnet"])
    ],
    targets: [
        .binaryTarget(name: "TailscaleKit", path: "TailscaleKit.xcframework"),
        .target(name: "Tailnet", dependencies: [.target(name: "TailscaleKit", condition: .when(platforms: [.iOS]))]),
    ]
)
