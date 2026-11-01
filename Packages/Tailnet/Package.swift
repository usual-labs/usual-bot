// swift-tools-version: 6.0
import PackageDescription

// TailscaleKit.xcframework comes from a usual-labs/tailscalekit-build release, built there from
// tailscale/libtailscale; Xcode downloads it and the checksum pins the exact file. The release
// notes give the next URL and checksum. It has iPhone and Simulator slices only, so the Mac build
// skips it.
let package = Package(
    name: "Tailnet",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "Tailnet", targets: ["Tailnet"])
    ],
    targets: [
        .binaryTarget(
            name: "TailscaleKit",
            url:
                "https://github.com/usual-labs/tailscalekit-build/releases/download/libtailscale-ac7ed43/TailscaleKit.xcframework.zip",
            checksum: "1c308de0376ca9ad96e9eed4a58831ec450d6d7c6c0b6572ce90a250cb71e7cb"),
        .target(name: "Tailnet", dependencies: [.target(name: "TailscaleKit", condition: .when(platforms: [.iOS]))]),
    ]
)
