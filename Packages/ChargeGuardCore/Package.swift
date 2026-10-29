// swift-tools-version:5.10
// ChargeGuardCore: Foundation-only logic shared by the app, the helper daemon and chargectl.
// No IOKit, AppKit, os or Combine imports, so it builds and tests on macOS, Linux and Windows.
import PackageDescription

let package = Package(
    name: "ChargeGuardCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ChargeGuardCore", targets: ["ChargeGuardCore"]),
    ],
    targets: [
        .target(name: "ChargeGuardCore"),
        .testTarget(name: "ChargeGuardCoreTests", dependencies: ["ChargeGuardCore"]),
    ]
)
