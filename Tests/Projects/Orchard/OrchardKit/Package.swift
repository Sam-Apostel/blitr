// swift-tools-version: 5.9
import PackageDescription

// The fixture's model layer: Foundation only, so it compiles on Linux unchanged.
let package = Package(
    name: "OrchardKit",
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "OrchardKit", targets: ["OrchardKit"]),
    ],
    targets: [
        .target(name: "OrchardKit"),
    ]
)
