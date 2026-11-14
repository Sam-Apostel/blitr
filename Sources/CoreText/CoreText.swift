import Foundation

// A CoreText stand-in so code that registers its bundled fonts compiles. Registration is a harmless
// success: the renderer already finds fonts that ship as a module's resources (project mode passes
// their folders to it), so `Font.custom("Name", size:)` works after this "registration" as it would
// on a device. Nothing else of CoreText is provided.

public typealias CFURL = URL
public typealias CFArray = NSArray
public typealias CFError = NSError
public typealias CFString = NSString

public enum CTFontManagerScope: UInt32, Sendable {
    case none = 0, process = 1, persistent = 2, session = 3, user = 2147483647
}

@discardableResult
public func CTFontManagerRegisterFontsForURL(_ fontURL: CFURL, _ scope: CTFontManagerScope, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool {
    true
}

@discardableResult
public func CTFontManagerUnregisterFontsForURL(_ fontURL: CFURL, _ scope: CTFontManagerScope, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool {
    true
}

public func CTFontManagerRegisterFontURLs(_ fontURLs: CFArray, _ scope: CTFontManagerScope, _ enabled: Bool,
                                          _ registrationHandler: ((CFArray, Bool) -> Bool)?) {
    _ = registrationHandler?(NSArray(), true)
}
