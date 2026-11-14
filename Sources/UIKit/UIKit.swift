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
