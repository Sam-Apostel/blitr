// swift-tools-version:6.0
import PackageDescription

// Native Skia is fetched by scripts/bootstrap.sh into Vendor/ (not committed).
let skiaLib = Context.packageDirectory + "/Vendor/skia/lib"

let package = Package(
    name: "swift-ui-screenshot",
    products: [
        // A Linux reimplementation of the SwiftUI API surface, named `SwiftUI`
        // so unmodified app code (`import SwiftUI`) compiles against it.
        .library(name: "SwiftUI", type: .dynamic, targets: ["SwiftUI"]),
        // The command-line tool: compiles user sources against the module above and renders them.
        .executable(name: "swiftui-screenshot", targets: ["swiftui-screenshot"]),
    ],
    targets: [
        .target(
            name: "CSkia",
            linkerSettings: [
                .linkedLibrary("SkiaSharp"),
                .unsafeFlags(["-L", skiaLib, "-Xlinker", "-rpath", "-Xlinker", skiaLib,
                              "-Xlinker", "-rpath", "-Xlinker", "$ORIGIN"]),
            ]
        ),
        .systemLibrary(name: "CHarfBuzz", pkgConfig: "harfbuzz", providers: [.apt(["libharfbuzz-dev"])]),
        .target(
            name: "SwiftUI",
            dependencies: ["CSkia", "CHarfBuzz"],
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-enable-library-evolution"])]
        ),
        .executableTarget(name: "swiftui-screenshot", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
