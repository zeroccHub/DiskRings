// swift-tools-version:5.9
//
// DiskRings — a clean-room macOS disk usage analyzer.
//
// Targets:
//   DiskScanCore      portable scan engine, tree model, hard-link dedup, deletion
//                     (Darwin getattrlistbulk enumerator compiled only on Darwin)
//   SunburstGeometry  pure-Swift ring/angle layout + hit testing (no UI deps)
//   DiskRingsApp      AppKit executable (real UI on macOS; prints a notice elsewhere)
import PackageDescription

let package = Package(
    name: "DiskRings",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "DiskScanCore", targets: ["DiskScanCore"]),
        .library(name: "SunburstGeometry", targets: ["SunburstGeometry"]),
        .executable(name: "DiskRings", targets: ["DiskRingsApp"]),
    ],
    targets: [
        .target(name: "DiskScanCore"),
        .target(name: "SunburstGeometry", dependencies: ["DiskScanCore"]),
        .executableTarget(
            name: "DiskRingsApp",
            dependencies: ["DiskScanCore", "SunburstGeometry"],
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("QuartzCore", .when(platforms: [.macOS])),
                .linkedFramework("Quartz", .when(platforms: [.macOS])),   // QLPreviewPanel
            ]
        ),
        .testTarget(name: "DiskScanCoreTests", dependencies: ["DiskScanCore"]),
        .testTarget(name: "SunburstGeometryTests", dependencies: ["SunburstGeometry", "DiskScanCore"]),
    ]
)
