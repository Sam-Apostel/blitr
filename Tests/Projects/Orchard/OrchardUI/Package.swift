// swift-tools-version: 5.9
import PackageDescription

// The fixture's design system: SwiftUI views, a bundled font and an asset catalog.
let package = Package(
    name: "OrchardUI",
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OrchardUI", targets: ["OrchardUI"]),
    ],
    targets: [
        .target(
            name: "OrchardUI",
            resources: [.process("Resources")]
        ),
    ]
)
