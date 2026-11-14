// swift-tools-version:6.0
import PackageDescription

// Native Skia is fetched by scripts/bootstrap.sh into Vendor/ (not committed).
let skiaLib = Context.packageDirectory + "/Vendor/skia/lib"

// Modules that user code imports are built with library evolution so their private
// C dependencies do not leak into the user's compile.
let moduleSettings: [SwiftSetting] = [.swiftLanguageMode(.v5), .unsafeFlags(["-enable-library-evolution"])]

let package = Package(
    name: "swift-ui-screenshot",
    products: [
        // A Linux reimplementation of the SwiftUI API surface, named `SwiftUI`
        // so unmodified app code (`import SwiftUI`) compiles against it.
        .library(name: "SwiftUI", type: .dynamic, targets: ["SwiftUI"]),
        // Shims so `import Combine` / `import UIKit` resolve (SwiftUI re-exports Combine).
        .library(name: "Combine", type: .dynamic, targets: ["Combine"]),
        .library(name: "UIKit", type: .dynamic, targets: ["UIKit"]),
        // Shims for widget extensions: `import WidgetKit`, `ActivityKit`, `AppIntents` (see docs/WIDGETS.md).
        .library(name: "AppIntents", type: .dynamic, targets: ["AppIntents"]),
        .library(name: "ActivityKit", type: .dynamic, targets: ["ActivityKit"]),
        .library(name: "WidgetKit", type: .dynamic, targets: ["WidgetKit"]),
        // The command-line tool: compiles user sources against the modules above and renders them.
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
        .target(name: "Combine", swiftSettings: moduleSettings),
        .target(name: "SwiftUI", dependencies: ["CSkia", "CHarfBuzz", "Combine"], swiftSettings: moduleSettings),
        .target(name: "UIKit", dependencies: ["SwiftUI"], swiftSettings: moduleSettings),
        .target(name: "AppIntents", dependencies: ["SwiftUI"], swiftSettings: moduleSettings),
        .target(name: "ActivityKit", dependencies: ["SwiftUI"], swiftSettings: moduleSettings),
        .target(name: "WidgetKit", dependencies: ["SwiftUI"], swiftSettings: moduleSettings),
        .executableTarget(name: "swiftui-screenshot", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
