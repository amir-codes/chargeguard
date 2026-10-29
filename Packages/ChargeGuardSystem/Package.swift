// swift-tools-version:5.10
// ChargeGuardSystem: macOS-only platform layer.
// - ChargeGuardSystem: IOKit SMC client, IORegistry battery reader, IOPM assertions, pmset, observers,
//   process scanning, powermetrics, persistence, XPC client. No AppKit, so the root daemon can use it.
// - ChargeGuardSessionKit: AppKit/NSWorkspace observers for the app (sleep/wake, user sessions, apps).
import PackageDescription

let package = Package(
    name: "ChargeGuardSystem",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ChargeGuardSystem", targets: ["ChargeGuardSystem"]),
        .library(name: "ChargeGuardSessionKit", targets: ["ChargeGuardSessionKit"]),
    ],
    dependencies: [
        .package(path: "../ChargeGuardCore"),
    ],
    targets: [
        .target(
            name: "ChargeGuardSystem",
            dependencies: [.product(name: "ChargeGuardCore", package: "ChargeGuardCore")],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Security")]
        ),
        .target(
            name: "ChargeGuardSessionKit",
            dependencies: ["ChargeGuardSystem"],
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .testTarget(
            name: "ChargeGuardSystemTests",
            dependencies: ["ChargeGuardSystem", .product(name: "ChargeGuardCore", package: "ChargeGuardCore")]
        ),
    ]
)
