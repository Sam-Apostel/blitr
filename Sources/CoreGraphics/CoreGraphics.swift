// `import CoreGraphics`: bitmap images (CGImage, CGDataProvider, CGColorSpace), colors, paths and a
// bitmap drawing context (CGContext), drawn with Skia. SwiftUI depends on this module and re-exports
// it, as Apple's SwiftUI makes Core Graphics visible: `Image(decorative: cgImage, scale:)` and
// `ImageRenderer.cgImage` take and give these types. Linked into libBlitrEngine (docs/ARCHITECTURE.md).
@_exported import Foundation

#if !canImport(Darwin)
// CoreFoundation names that Core Graphics, ImageIO, CoreText and Security signatures mention. On Linux
// they are the Foundation classes they are toll-free bridged to on Apple platforms, so `data as CFData`,
// `url as CFURL`, `[k: v] as CFDictionary` and `dict as? [CFString: Any]` all work.
public typealias CFTypeRef = AnyObject
public typealias CFIndex = Int
public typealias CFString = NSString
public typealias CFData = NSData
public typealias CFMutableData = NSMutableData
public typealias CFURL = NSURL
public typealias CFDictionary = NSDictionary
public typealias CFMutableDictionary = NSMutableDictionary
public typealias CFArray = NSArray
public typealias CFNumber = NSNumber
public typealias CFBoolean = NSNumber
public typealias CFError = NSError
public typealias CFTimeInterval = Double
public typealias CFAbsoluteTime = Double

public func CFAbsoluteTimeGetCurrent() -> CFAbsoluteTime { Date().timeIntervalSinceReferenceDate }
public let kCFBooleanTrue: CFBoolean = true
public let kCFBooleanFalse: CFBoolean = false
#endif

/// How framework shims report what they could not do: SwiftUI's runtime installs the handler, which
/// shows each message once as a render warning. Callable from any thread.
package enum ShimDiagnostics {
    nonisolated(unsafe) package static var handler: ((String) -> Void)?
    package static func warn(_ message: String) { handler?(message) }
}

/// Unboxes a number stored in an options dictionary.
package func _cfNumber(_ value: Any?) -> Double? {
    if let n = value as? NSNumber { return n.doubleValue }
    if let d = value as? Double { return d }
    if let i = value as? Int { return Double(i) }
    if let f = value as? CGFloat { return Double(f) }
    if let b = value as? Bool { return b ? 1 : 0 }
    return nil
}

/// Font files registered at run time (CTFontManagerRegisterFontsForURL, CTFontManagerRegisterGraphicsFont).
/// The SwiftUI font library looks here before its font directories.
package enum FontRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var registered: [String] = []
    package static var paths: [String] { lock.lock(); defer { lock.unlock() }; return registered }
    package static func add(_ path: String) { lock.lock(); if !registered.contains(path) { registered.append(path) }; lock.unlock() }
    package static func remove(_ path: String) { lock.lock(); registered.removeAll { $0 == path }; lock.unlock() }
    /// Bumped on every change, so caches keyed on the registry can notice.
    package static var generation: Int { lock.lock(); defer { lock.unlock() }; return registered.count }
}

/// A CFString constant from text: on Linux CFString is NSString, on Darwin it is CoreFoundation's own type.
@inline(__always) package func _cfString(_ text: String) -> CFString {
    #if canImport(Darwin)
    return text as CFString
    #else
    return NSString(string: text)
    #endif
}
