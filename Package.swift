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
        // Shims so `import Combine` / `import UIKit` resolve (SwiftUI re-exports both).
        .library(name: "Combine", type: .dynamic, targets: ["Combine"]),
        .library(name: "UIKit", type: .dynamic, targets: ["UIKit"]),
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
            name: "Combine",
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-enable-library-evolution"])]
        ),
        .target(
            name: "SwiftUI",
            dependencies: ["CSkia", "CHarfBuzz", "Combine"],
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-enable-library-evolution"])]
        ),
        .target(
            name: "UIKit",
            dependencies: ["SwiftUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
