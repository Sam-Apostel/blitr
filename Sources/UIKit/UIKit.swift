// `import UIKit`: UIColor, UIImage, UIFont, the UIKit singletons (UIScreen, UIDevice, UIApplication, ...)
// and inert UIView/UIViewController shells.
//
// On iOS, tvOS and visionOS Apple's SwiftUI re-exports UIKit, so the preprocessor adds `import UIKit` next
// to every `import SwiftUI` when rendering those platforms; on macOS and watchOS these names stay hidden.
// The SwiftUI API that takes UIKit types (`Color(uiColor:)`, `Image(uiImage:)`, `Font(_: UIFont)`,
// `UIViewRepresentable`, `UIHostingController`, `@UIApplicationDelegateAdaptor`, `keyboardType(_:)`,
// `ImageRenderer.uiImage`) is declared here, next to those types, because this module builds on SwiftUI.
@_exported import Foundation
@_exported import QuartzCore
@_exported import Security
// Foundation types that this package declares in SwiftUI, visible wherever UIKit is imported (they are
// Foundation's on Apple platforms).
@_exported import class SwiftUI.NSItemProvider
@_exported import class SwiftUI.NSUserActivity
@_exported import struct UniformTypeIdentifiers.UTType
