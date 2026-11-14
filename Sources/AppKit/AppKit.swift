// `import AppKit` (importable when rendering macOS: `#if canImport(AppKit)` is false elsewhere): the
// value types macOS code passes into SwiftUI (NSColor with appearance-dependent colors, NSImage, NSFont),
// NSViewRepresentable (shown as a placeholder), and inert pasteboard, workspace and application objects.
@_exported import SwiftUI
@_exported import QuartzCore
import ImageIO

public struct NSAppearanceName: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let aqua = NSAppearanceName("NSAppearanceNameAqua")
    public static let darkAqua = NSAppearanceName("NSAppearanceNameDarkAqua")
    public static let vibrantLight = NSAppearanceName("NSAppearanceNameVibrantLight")
    public static let vibrantDark = NSAppearanceName("NSAppearanceNameVibrantDark")
    public static let accessibilityHighContrastAqua = NSAppearanceName("NSAppearanceNameAccessibilityAqua")
    public static let accessibilityHighContrastDarkAqua = NSAppearanceName("NSAppearanceNameAccessibilityDarkAqua")
}
open class NSAppearance: NSObject, @unchecked Sendable {
    public let name: NSAppearanceName
    public init?(named name: NSAppearanceName) { self.name = name; super.init() }
    init(name: NSAppearanceName) { self.name = name; super.init() }
    /// The appearance being rendered.
    public class var currentDrawing: NSAppearance { NSAppearance(name: _currentConfiguration().colorScheme == .dark ? .darkAqua : .aqua) }
    public class var current: NSAppearance! { currentDrawing }
    open func bestMatch(from appearances: [NSAppearanceName]) -> NSAppearanceName? {
        let dark = name == .darkAqua || name == .vibrantDark || name == .accessibilityHighContrastDarkAqua
        return appearances.first { ($0 == .darkAqua || $0 == .vibrantDark || $0 == .accessibilityHighContrastDarkAqua) == dark }
    }
    open func performAsCurrentDrawingAppearance(_ block: () -> Void) { block() }
}

open class NSColor: NSObject, @unchecked Sendable {
    let dynamic: DynamicColor
    init(_ dynamic: DynamicColor) { self.dynamic = dynamic; super.init() }
    convenience init(_ rgba: RGBA) { self.init(DynamicColor(light: rgba, dark: rgba)) }
    public convenience init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { self.init(RGBA(Double(red), Double(green), Double(blue), Double(alpha))) }
    public convenience init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { self.init(red: red, green: green, blue: blue, alpha: alpha) }
    public convenience init(calibratedRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { self.init(red: red, green: green, blue: blue, alpha: alpha) }
    public convenience init(displayP3Red red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { self.init(red: red, green: green, blue: blue, alpha: alpha) }
    public convenience init(white: CGFloat, alpha: CGFloat) { self.init(red: white, green: white, blue: white, alpha: alpha) }
    public convenience init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
        self.init(Color(hue: Double(hue), saturation: Double(saturation), brightness: Double(brightness), opacity: Double(alpha)).rgba(in: EnvironmentValues()))
    }
    public convenience init(cgColor: CGColor) { self.init(RGBA(cgColor.rgba.r, cgColor.rgba.g, cgColor.rgba.b, cgColor.rgba.a)) }
    public convenience init(_ color: Color) {
        var light = EnvironmentValues(), dark = EnvironmentValues()
        light.colorScheme = .light
        dark.colorScheme = .dark
        self.init(DynamicColor(light: color.rgba(in: light), dark: color.rgba(in: dark)))
    }
    /// Resolved once per appearance, light (aqua) and dark (darkAqua).
    public convenience init(name colorName: String?, dynamicProvider: @escaping (NSAppearance) -> NSColor) {
        self.init(DynamicColor(light: dynamicProvider(NSAppearance(name: .aqua)).dynamic.light, dark: dynamicProvider(NSAppearance(name: .darkAqua)).dynamic.dark))
    }
    public convenience init?(named name: String) {
        let found: DynamicColor? = Thread.isMainThread ? MainActor.assumeIsolated {
            guard let light = AssetCatalog.shared.color(named: name, scheme: .light) else { return nil }
            return DynamicColor(light: light, dark: AssetCatalog.shared.color(named: name, scheme: .dark) ?? light)
        } : nil
        self.init(found ?? DynamicColor(light: RGBA(1, 0, 1, 1), dark: RGBA(1, 0, 1, 1)))
    }
    private var current: RGBA { _currentConfiguration().colorScheme == .dark ? dynamic.dark : dynamic.light }
    public var cgColor: CGColor { CGColor(srgbRed: current.r, green: current.g, blue: current.b, alpha: current.a) }
    public var redComponent: CGFloat { CGFloat(current.r) }
    public var greenComponent: CGFloat { CGFloat(current.g) }
    public var blueComponent: CGFloat { CGFloat(current.b) }
    public var alphaComponent: CGFloat { CGFloat(current.a) }
    public func withAlphaComponent(_ alpha: CGFloat) -> NSColor {
        NSColor(DynamicColor(light: RGBA(dynamic.light.r, dynamic.light.g, dynamic.light.b, Double(alpha)), dark: RGBA(dynamic.dark.r, dynamic.dark.g, dynamic.dark.b, Double(alpha))))
    }
    public func usingColorSpace(_ space: AnyObject) -> NSColor? { self }
    public func getRed(_ red: UnsafeMutablePointer<CGFloat>?, green: UnsafeMutablePointer<CGFloat>?, blue: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) {
        red?.pointee = redComponent; green?.pointee = greenComponent; blue?.pointee = blueComponent; alpha?.pointee = alphaComponent
    }
    public func setFill() {}
    public func setStroke() {}
    public func set() {}

    public static var black: NSColor { NSColor(RGBA.black) }
    public static var white: NSColor { NSColor(RGBA.white) }
    public static var clear: NSColor { NSColor(RGBA.clear) }
    public static var red: NSColor { NSColor(Color.red) }
    public static var green: NSColor { NSColor(Color.green) }
    public static var blue: NSColor { NSColor(Color.blue) }
    public static var orange: NSColor { NSColor(Color.orange) }
    public static var yellow: NSColor { NSColor(Color.yellow) }
    public static var purple: NSColor { NSColor(Color.purple) }
    public static var gray: NSColor { NSColor(Color.gray) }
    public static var systemRed: NSColor { .red }
    public static var systemGreen: NSColor { .green }
    public static var systemBlue: NSColor { .blue }
    public static var systemOrange: NSColor { .orange }
    public static var systemYellow: NSColor { .yellow }
    public static var systemPurple: NSColor { .purple }
    public static var systemGray: NSColor { .gray }
    public static var labelColor: NSColor { NSColor(Color.primary) }
    public static var secondaryLabelColor: NSColor { NSColor(Color.secondary) }
    public static var controlAccentColor: NSColor { NSColor(Color.accentColor) }
    public static var windowBackgroundColor: NSColor { NSColor(DynamicColor(light: RGBA(0.93, 0.93, 0.93, 1), dark: RGBA(0.16, 0.16, 0.16, 1))) }
    public static var textBackgroundColor: NSColor { NSColor(DynamicColor(light: RGBA.white, dark: RGBA(0.12, 0.12, 0.12, 1))) }
    public static var controlBackgroundColor: NSColor { textBackgroundColor }
    public static var separatorColor: NSColor { NSColor(DynamicColor(light: RGBA(0, 0, 0, 0.1), dark: RGBA(1, 1, 1, 0.1))) }
}
extension Color {
    public init(nsColor: NSColor) { self.init(nsColor.dynamic) }
    public init(_ color: NSColor) { self.init(color.dynamic) }
}

open class NSImage: NSObject, @unchecked Sendable {
    public enum Name: Hashable, Sendable { case applicationIcon, caution, folder, network }
    let rendered: RenderedImage?
    let named: String?
    open var size: CGSize
    init(rendered: RenderedImage?, named: String?, size: CGSize) { self.rendered = rendered; self.named = named; self.size = size; super.init() }
    public convenience init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as NSData, nil), let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.init(cgImage: cg, size: .zero)
    }
    public convenience init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }
    public convenience init?(contentsOfFile path: String) { self.init(contentsOf: URL(fileURLWithPath: path)) }
    public convenience init(cgImage: CGImage, size: CGSize) {
        let s = size == .zero ? CGSize(width: cgImage.width, height: cgImage.height) : size
        self.init(rendered: RenderedImage(cgImage: cgImage, scale: CGFloat(cgImage.width) / max(s.width, 1)), named: nil, size: s)
    }
    public convenience init?(named name: String) { self.init(rendered: nil, named: name, size: .zero) }
    public convenience init?(systemSymbolName name: String, accessibilityDescription: String?) { self.init(rendered: nil, named: "system:" + name, size: CGSize(width: 17, height: 17)) }
    public convenience init(size: CGSize) { self.init(rendered: nil, named: nil, size: size) }
    public func cgImage(forProposedRect proposedDestRect: UnsafeMutablePointer<CGRect>?, context: AnyObject?, hints: [AnyHashable: Any]?) -> CGImage? { rendered?.cgImage }
    public var tiffRepresentation: Data? { nil }
    open var isTemplate = false
}
extension Image {
    public init(nsImage: NSImage) {
        self.init("")
        if let rendered = nsImage.rendered { source = .rendered(rendered) }
        else if let named = nsImage.named { source = named.hasPrefix("system:") ? .system(String(named.dropFirst(7))) : .named(named) }
        if nsImage.isTemplate { renderingMode = .template }
    }
}

open class NSFont: NSObject, @unchecked Sendable {
    public typealias Weight = Font.Weight
    let font: Font
    public let pointSize: CGFloat
    public let fontName: String
    init(font: Font, pointSize: CGFloat, name: String) { self.font = font; self.pointSize = pointSize; fontName = name; super.init() }
    public static func systemFont(ofSize size: CGFloat) -> NSFont { NSFont(font: .system(size: size), pointSize: size, name: ".AppleSystemUIFont") }
    public static func systemFont(ofSize size: CGFloat, weight: Font.Weight) -> NSFont { NSFont(font: .system(size: size, weight: weight), pointSize: size, name: ".AppleSystemUIFont") }
    public static func boldSystemFont(ofSize size: CGFloat) -> NSFont { NSFont(font: .system(size: size, weight: .bold), pointSize: size, name: ".AppleSystemUIFontBold") }
    public static func monospacedSystemFont(ofSize size: CGFloat, weight: Font.Weight) -> NSFont {
        NSFont(font: .system(size: size, weight: weight, design: .monospaced), pointSize: size, name: ".AppleSystemUIFontMonospaced")
    }
    public convenience init?(name: String, size: CGFloat) { self.init(font: .custom(name, fixedSize: size), pointSize: size, name: name) }
}
extension Font {
    public init(_ font: NSFont) { self = font.font }
}

open class NSResponder: NSObject {}
open class NSView: NSResponder {
    open var frame: CGRect = .zero
    open var bounds: CGRect { CGRect(origin: .zero, size: frame.size) }
    open var wantsLayer = false
    open var layer: CALayer?
    open var isHidden = false
    open var subviews: [NSView] = []
    public init(frame frameRect: CGRect) { frame = frameRect; super.init() }
    public convenience override init() { self.init(frame: .zero) }
    open func addSubview(_ view: NSView) { subviews.append(view) }
}
open class NSViewController: NSResponder {
    open var view = NSView()
    public override init() { super.init() }
}
open class NSHostingView<Content: View>: NSView {
    public var rootView: Content
    public init(rootView: Content) { self.rootView = rootView; super.init(frame: .zero) }
}
open class NSHostingController<Content: View>: NSViewController {
    public var rootView: Content
    public init(rootView: Content) { self.rootView = rootView; super.init() }
}

public struct NSViewRepresentableContext<Representable: NSViewRepresentable> {
    public let coordinator: Representable.Coordinator
    public var transaction = Transaction()
    public var environment = EnvironmentValues()
}
/// Shown as a placeholder of the proposed size naming the wrapped class.
public protocol NSViewRepresentable: View where Body == _RepresentablePlaceholder {
    associatedtype NSViewType: NSView
    associatedtype Coordinator = Void
    typealias Context = NSViewRepresentableContext<Self>
    @MainActor func makeNSView(context: Context) -> NSViewType
    @MainActor func updateNSView(_ nsView: NSViewType, context: Context)
    @MainActor func makeCoordinator() -> Coordinator
}
extension NSViewRepresentable {
    public var body: _RepresentablePlaceholder { _RepresentablePlaceholder(typeName: String(describing: Self.self), wrapping: String(describing: NSViewType.self)) }
}
extension NSViewRepresentable where Coordinator == Void {
    public func makeCoordinator() -> Void {}
}
public struct NSViewControllerRepresentableContext<Representable: NSViewControllerRepresentable> {
    public let coordinator: Representable.Coordinator
    public var transaction = Transaction()
    public var environment = EnvironmentValues()
}
public protocol NSViewControllerRepresentable: View where Body == _RepresentablePlaceholder {
    associatedtype NSViewControllerType: NSViewController
    associatedtype Coordinator = Void
    typealias Context = NSViewControllerRepresentableContext<Self>
    @MainActor func makeNSViewController(context: Context) -> NSViewControllerType
    @MainActor func updateNSViewController(_ nsViewController: NSViewControllerType, context: Context)
    @MainActor func makeCoordinator() -> Coordinator
}
extension NSViewControllerRepresentable {
    public var body: _RepresentablePlaceholder { _RepresentablePlaceholder(typeName: String(describing: Self.self), wrapping: String(describing: NSViewControllerType.self)) }
}
extension NSViewControllerRepresentable where Coordinator == Void {
    public func makeCoordinator() -> Void {}
}

/// An in-memory pasteboard.
open class NSPasteboard: NSObject, @unchecked Sendable {
    public struct PasteboardType: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static let string = PasteboardType("public.utf8-plain-text")
        public static let URL = PasteboardType("public.url")
        public static let fileURL = PasteboardType("public.file-url")
        public static let png = PasteboardType("public.png")
        public static let tiff = PasteboardType("public.tiff")
        public static let pdf = PasteboardType("com.adobe.pdf")
        public static let html = PasteboardType("public.html")
        public static let rtf = PasteboardType("public.rtf")
    }
    public static let general = NSPasteboard()
    private var items: [PasteboardType: Any] = [:]
    public private(set) var changeCount = 0
    @discardableResult open func clearContents() -> Int { items = [:]; changeCount += 1; return changeCount }
    @discardableResult open func setString(_ string: String, forType dataType: PasteboardType) -> Bool { items[dataType] = string; changeCount += 1; return true }
    @discardableResult open func setData(_ data: Data?, forType dataType: PasteboardType) -> Bool { items[dataType] = data; changeCount += 1; return true }
    open func string(forType dataType: PasteboardType) -> String? { items[dataType] as? String }
    open func data(forType dataType: PasteboardType) -> Data? { items[dataType] as? Data }
    open var types: [PasteboardType]? { Array(items.keys) }
    @discardableResult open func declareTypes(_ newTypes: [PasteboardType], owner newOwner: Any?) -> Int { changeCount }
}

/// Nothing is opened.
open class NSWorkspace: NSObject, @unchecked Sendable {
    public static let shared = NSWorkspace()
    @discardableResult open func open(_ url: URL) -> Bool { false }
    open func activateFileViewerSelecting(_ fileURLs: [URL]) {}
    open func icon(forFile fullPath: String) -> NSImage { NSImage(size: CGSize(width: 32, height: 32)) }
}

open class NSApplication: NSResponder, @unchecked Sendable {
    public enum ActivationPolicy: Int, Sendable { case regular, accessory, prohibited }
    nonisolated(unsafe) public static let shared = NSApplication()
    public static let didBecomeActiveNotification = Notification.Name("NSApplicationDidBecomeActiveNotification")
    public static let willTerminateNotification = Notification.Name("NSApplicationWillTerminateNotification")
    open var isActive: Bool { true }
    open var appearance: NSAppearance?
    open var effectiveAppearance: NSAppearance { NSAppearance.currentDrawing }
    open var windows: [AnyObject] { [] }
    open func activate(ignoringOtherApps flag: Bool) {}
    open func activate() {}
    open func terminate(_ sender: Any?) {}
    @discardableResult open func setActivationPolicy(_ activationPolicy: ActivationPolicy) -> Bool { true }
}
public let NSApp = NSApplication.shared
public protocol NSApplicationDelegate: AnyObject {}

@propertyWrapper
public struct NSApplicationDelegateAdaptor<DelegateType: NSObject & NSApplicationDelegate>: DynamicProperty {
    public init(_ delegateType: DelegateType.Type = DelegateType.self) {}
    public var wrappedValue: DelegateType { fatalError("@NSApplicationDelegateAdaptor: the \(DelegateType.self) instance is not available when rendering") }
}

extension DynamicColor {
    init(light: RGBA, dark: RGBA) {
        self.init(0, 0)
        self.light = light
        self.dark = dark
    }
}
