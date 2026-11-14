// swift-tools-version:6.0
import PackageDescription

// Native Skia is fetched by scripts/bootstrap.sh into Vendor/ (not committed).
let skiaLib = Context.packageDirectory + "/Vendor/skia/lib"

// Modules that user code imports are built with library evolution so their private
// C dependencies do not leak into the user's compile.
let moduleSettings: [SwiftSetting] = [.swiftLanguageMode(.v5), .unsafeFlags(["-enable-library-evolution"])]

// Modules linked into libSwiftUI next to the SwiftUI module itself (Combine is a dependency of SwiftUI).
let shimModules = ["Combine", "UniformTypeIdentifiers", "CoreGraphics", "ImageIO", "CoreImage", "CoreText", "ObjectiveC", "QuartzCore", "UIKit", "CoreLocation", "MapKit", "AppIntents", "ActivityKit", "WidgetKit", "CryptoKit", "Security", "Network", "CoreSpotlight", "UserNotifications", "EventKit", "WatchConnectivity", "Contacts", "PhotosUI", "AuthenticationServices", "PassKit", "PDFKit", "Vision", "VisionKit", "EventKitUI", "ContactsUI", "Translation", "QuickLook", "AppKit", "StoreKit", "AVFoundation", "AVKit", "SafariServices", "MessageUI", "CoreMotion", "CoreHaptics", "TipKit", "os", "OSLog", "WatchKit"]

let package = Package(
    name: "swift-ui-screenshot",
    products: [
        // A Linux reimplementation of the SwiftUI API surface, named `SwiftUI` so unmodified app code
        // (`import SwiftUI`) compiles against it. The shim frameworks (`import UIKit`, `MapKit`, `WidgetKit`, ...)
        // are separate modules, so their names are only visible where they are imported, but their code is
        // linked into this one library: a dynamic library of their own would carry a second copy of SwiftUI
        // (SwiftPM links a target's dependencies into every dynamic product), and two copies in a process
        // break protocol conformance lookups at run time. Importers link `-lSwiftUI` (docs/ARCHITECTURE.md).
        .library(name: "SwiftUI", type: .dynamic, targets: ["SwiftUI"] + shimModules),
        // Foundation's localization API (String(localized:), LocalizedStringResource), which Linux Foundation
        // lacks; SwiftUI re-exports it and project mode imports it into Foundation-only packages.
        .library(name: "SwiftUIScreenshotFoundation", type: .dynamic, targets: ["SwiftUIScreenshotFoundation"]),
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
        // Autolinked (-module-link-name), so importers need no extra -l flag.
        .target(name: "SwiftUIScreenshotFoundation", swiftSettings: moduleSettings + [.unsafeFlags(["-module-link-name", "SwiftUIScreenshotFoundation"])]),
        // Core Graphics sits below SwiftUI (Apple's SwiftUI re-exports it); ImageIO and CoreText build on it.
        .target(name: "CoreGraphics", dependencies: ["CSkia"], swiftSettings: moduleSettings),
        .target(name: "ImageIO", dependencies: ["CoreGraphics", "CSkia"], swiftSettings: moduleSettings),
        .target(name: "CoreText", dependencies: ["CoreGraphics", "CSkia"], swiftSettings: moduleSettings),
        .target(name: "CoreImage", dependencies: ["CoreGraphics", "ImageIO", "CSkia"], swiftSettings: moduleSettings),
        .target(name: "ObjectiveC", swiftSettings: moduleSettings),
        .target(name: "UniformTypeIdentifiers", swiftSettings: moduleSettings),
        .target(name: "QuartzCore", dependencies: ["CoreGraphics", "ObjectiveC"], swiftSettings: moduleSettings),
        .target(name: "SwiftUI", dependencies: ["CSkia", "CHarfBuzz", "Combine", "CoreGraphics", "UniformTypeIdentifiers", "SwiftUIScreenshotFoundation"], swiftSettings: moduleSettings),
        // The shim frameworks: each its own module, linked into libSwiftUI (see the SwiftUI product).
        .target(name: "UIKit", dependencies: ["SwiftUI", "QuartzCore", "ImageIO", "CoreImage", "Security", "CSkia"], swiftSettings: moduleSettings),
        .target(name: "AppIntents", dependencies: ["SwiftUI", "UIKit"], swiftSettings: moduleSettings),
        .target(name: "ActivityKit", dependencies: ["SwiftUIScreenshotFoundation"], swiftSettings: moduleSettings),
        .target(name: "WidgetKit", dependencies: ["SwiftUI", "AppIntents", "ActivityKit"], swiftSettings: moduleSettings),
        .target(name: "CoreLocation", swiftSettings: moduleSettings),
        .target(name: "MapKit", dependencies: ["SwiftUI", "UIKit", "CoreLocation"], swiftSettings: moduleSettings),
        .target(name: "CryptoKit", swiftSettings: moduleSettings),
        .target(name: "Security", dependencies: ["CoreGraphics"], swiftSettings: moduleSettings),
        .target(name: "Network", swiftSettings: moduleSettings),
        .target(name: "CoreSpotlight", dependencies: ["UniformTypeIdentifiers"], swiftSettings: moduleSettings),
        .target(name: "UserNotifications", swiftSettings: moduleSettings),
        .target(name: "EventKit", dependencies: ["CoreGraphics", "CoreLocation"], swiftSettings: moduleSettings),
        .target(name: "WatchConnectivity", swiftSettings: moduleSettings),
        .target(name: "TipKit", dependencies: ["SwiftUI"], swiftSettings: moduleSettings),
        .target(name: "os", swiftSettings: moduleSettings),
        .target(name: "WatchKit", dependencies: ["SwiftUI"], swiftSettings: moduleSettings),
        .target(name: "OSLog", dependencies: ["os"], swiftSettings: moduleSettings),
        .target(name: "Contacts", swiftSettings: moduleSettings),
        .target(name: "PhotosUI", dependencies: ["SwiftUI", "UIKit", "UniformTypeIdentifiers"], swiftSettings: moduleSettings),
        .target(name: "AuthenticationServices", dependencies: ["SwiftUI", "UIKit", "Security"], swiftSettings: moduleSettings),
        .target(name: "PassKit", dependencies: ["SwiftUI", "UIKit"], swiftSettings: moduleSettings),
        .target(name: "PDFKit", dependencies: ["UIKit"], swiftSettings: moduleSettings),
        .target(name: "Vision", dependencies: ["CoreImage"], swiftSettings: moduleSettings),
        .target(name: "VisionKit", dependencies: ["UIKit", "Vision"], swiftSettings: moduleSettings),
        .target(name: "EventKitUI", dependencies: ["UIKit", "EventKit"], swiftSettings: moduleSettings),
        .target(name: "ContactsUI", dependencies: ["UIKit", "Contacts"], swiftSettings: moduleSettings),
        .target(name: "Translation", dependencies: ["SwiftUI"], swiftSettings: moduleSettings),
        .target(name: "QuickLook", dependencies: ["SwiftUI", "UIKit"], swiftSettings: moduleSettings),
        .target(name: "AppKit", dependencies: ["SwiftUI", "QuartzCore", "ImageIO"], swiftSettings: moduleSettings),
        .target(name: "StoreKit", dependencies: ["SwiftUI"], swiftSettings: moduleSettings),
        .target(name: "AVFoundation", dependencies: ["CoreGraphics"], swiftSettings: moduleSettings),
        .target(name: "AVKit", dependencies: ["SwiftUI", "AVFoundation"], swiftSettings: moduleSettings),
        .target(name: "SafariServices", dependencies: ["UIKit"], swiftSettings: moduleSettings),
        .target(name: "MessageUI", dependencies: ["UIKit"], swiftSettings: moduleSettings),
        .target(name: "CoreMotion", swiftSettings: moduleSettings),
        .target(name: "CoreHaptics", swiftSettings: moduleSettings),
        .executableTarget(name: "swiftui-screenshot", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
