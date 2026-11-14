internal import CSkia

// The engine side of widget rendering. The public widget API (Widget, WidgetFamily, the
// `\.widgetFamily` environment value, ...) lives in the WidgetKit shim module; it reaches the
// engine through the underscored hooks declared here, which are not part of Apple's API.
//
// A widget renders as `_WidgetCanvas`: the family's size for the selected device, the system
// corner radius, default content margins, the container background, and transparent pixels
// outside the rounded shape. See docs/WIDGETS.md.

// MARK: - Identifiers shared with WidgetKit

public enum _WidgetFamilyID: String, CaseIterable, Sendable {
    case systemSmall, systemMedium, systemLarge, systemExtraLarge
    case accessoryCircular, accessoryRectangular, accessoryInline

    public var _isAccessory: Bool { self == .accessoryCircular || self == .accessoryRectangular || self == .accessoryInline }

    /// Accepts `systemSmall`, `system-small`, `small`, `accessory-circular`, `circular`, ...
    public init?(_argument raw: String) {
        let key = raw.lowercased().filter { $0.isLetter }
        guard let match = Self.allCases.first(where: { family in
            let name = family.rawValue.lowercased()
            return key == name || key == name.replacingOccurrences(of: "system", with: "").replacingOccurrences(of: "accessory", with: "")
        }) else { return nil }
        self = match
    }
}

public enum _WidgetRenderingModeID: String, CaseIterable, Sendable {
    case fullColor, accented, vibrant

    public init?(_argument raw: String) {
        let key = raw.lowercased().filter { $0.isLetter }
        guard let match = Self.allCases.first(where: { $0.rawValue.lowercased() == key || ($0 == .fullColor && key == "full") }) else { return nil }
        self = match
    }
}

// MARK: - Environment (read through WidgetKit's public accessors)

private enum WidgetFamilyKey: EnvironmentKey { static let defaultValue = _WidgetFamilyID.systemSmall }
private enum WidgetRenderingModeKey: EnvironmentKey { static let defaultValue = _WidgetRenderingModeID.fullColor }
private enum ShowsWidgetBackgroundKey: EnvironmentKey { static let defaultValue = true }
private enum WidgetContentMarginsKey: EnvironmentKey { static let defaultValue = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16) }
private enum WidgetAccentedGroupKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    public var _widgetFamily: _WidgetFamilyID {
        get { self[WidgetFamilyKey.self] }
        set { self[WidgetFamilyKey.self] = newValue }
    }
    public var _widgetRenderingMode: _WidgetRenderingModeID {
        get { self[WidgetRenderingModeKey.self] }
        set { self[WidgetRenderingModeKey.self] = newValue }
    }
    public var _showsWidgetContainerBackground: Bool {
        get { self[ShowsWidgetBackgroundKey.self] }
        set { self[ShowsWidgetBackgroundKey.self] = newValue }
    }
    public var _widgetContentMargins: EdgeInsets {
        get { self[WidgetContentMarginsKey.self] }
        set { self[WidgetContentMarginsKey.self] = newValue }
    }
}

// MARK: - Command-line options

/// Widget options from the runner's command line. They are read straight from the arguments
/// because the list of previews (one per family or timeline entry) is built before the runner
/// parses its options.
public struct _WidgetHostOptions: Sendable {
    public var family: _WidgetFamilyID?
    public var renderingMode: _WidgetRenderingModeID?
    public var deviceName: String?

    public static let current = _WidgetHostOptions(arguments: CommandLine.arguments)

    init(arguments: [String]) {
        var args = arguments[...]
        while let arg = args.popFirst() {
            switch arg {
            case "--widget-family": family = args.popFirst().flatMap { _WidgetFamilyID(_argument: $0) }
            case "--widget-rendering-mode": renderingMode = args.popFirst().flatMap { _WidgetRenderingModeID(_argument: $0) }
            case "--device": deviceName = args.popFirst()
            default: break
            }
        }
    }
}

// MARK: - Metrics

enum WidgetMetrics {
    /// Widget sizes in points, from Apple's Human Interface Guidelines, "Widgets" > Specifications
    /// (https://developer.apple.com/design/human-interface-guidelines/widgets, table revision of
    /// October 13, 2026). One row per portrait screen size:
    /// small, medium, large, accessory circular, rectangular, inline.
    static let phoneTable: [(screen: CGSize, sizes: [CGSize])] = [
        row(430, 932, [(170, 170), (364, 170), (364, 382), (76, 76), (172, 76), (257, 26)]),
        row(428, 926, [(170, 170), (364, 170), (364, 382), (76, 76), (172, 76), (257, 26)]),
        row(414, 896, [(169, 169), (360, 169), (360, 379), (76, 76), (160, 72), (248, 26)]),
        row(414, 736, [(159, 159), (348, 157), (348, 357), (76, 76), (170, 76), (248, 26)]),
        row(393, 852, [(158, 158), (338, 158), (338, 354), (72, 72), (160, 72), (234, 26)]),
        row(390, 844, [(158, 158), (338, 158), (338, 354), (72, 72), (160, 72), (234, 26)]),
        row(375, 812, [(155, 155), (329, 155), (329, 345), (72, 72), (157, 72), (225, 26)]),
        row(375, 667, [(148, 148), (321, 148), (321, 324), (68, 68), (153, 68), (225, 26)]),
        row(360, 780, [(155, 155), (329, 155), (329, 345), (72, 72), (157, 72), (225, 26)]),
    ]
    /// iPad "Canvas" sizes from the same page (the size the widget's view is laid out at; the
    /// Home Screen then scales it to the "Device" size): small, medium, large, extra large.
    static let padTable: [(screen: CGSize, sizes: [CGSize])] = [
        row(768, 1024, [(141, 141), (305.5, 141), (305.5, 305.5), (634.5, 305.5)]),
        row(744, 1133, [(141, 141), (305.5, 141), (305.5, 305.5), (634.5, 305.5)]),
        row(810, 1080, [(146, 146), (320.5, 146), (320.5, 320.5), (669, 320.5)]),
        row(820, 1180, [(155, 155), (342, 155), (342, 342), (715.5, 342)]),
        row(834, 1112, [(150, 150), (327.5, 150), (327.5, 327.5), (682, 327.5)]),
        row(834, 1194, [(155, 155), (342, 155), (342, 342), (715.5, 342)]),
        row(954, 1373, [(162, 162), (350, 162), (350, 350), (726, 350)]),
        row(970, 1389, [(162, 162), (350, 162), (350, 350), (726, 350)]),
        row(1024, 1366, [(170, 170), (378.5, 170), (378.5, 378.5), (795, 378.5)]),
        row(1192, 1590, [(188, 188), (412, 188), (412, 412), (860, 412)]),
    ]

    private static func row(_ w: CGFloat, _ h: CGFloat, _ sizes: [(CGFloat, CGFloat)]) -> (screen: CGSize, sizes: [CGSize]) {
        (CGSize(width: w, height: h), sizes.map { CGSize(width: $0.0, height: $0.1) })
    }

    /// The table row for a device: an exact screen-size match, else the nearest one (by width,
    /// then height). Screens newer than the table (402x874, 440x956, 420x912) take the nearest row.
    private static func nearest(_ table: [(screen: CGSize, sizes: [CGSize])], _ screen: CGSize) -> (row: [CGSize], exact: Bool) {
        if let exact = table.first(where: { $0.screen == screen }) { return (exact.sizes, true) }
        let best = table.min { a, b in
            (abs(a.screen.width - screen.width), abs(a.screen.height - screen.height))
                < (abs(b.screen.width - screen.width), abs(b.screen.height - screen.height))
        }!
        return (best.sizes, false)
    }

    struct Resolved {
        var size: CGSize
        var cornerRadius: CGFloat
        var margins: EdgeInsets
        var fromTable: Bool
    }

    static func resolve(_ family: _WidgetFamilyID, device: DeviceProfile) -> Resolved? {
        let screen = device.portraitSize
        switch device.idiom {
        case .tv: return nil
        case .phone:
            let (row, exact) = nearest(phoneTable, screen)
            let index: Int
            switch family {
            case .systemSmall: index = 0
            case .systemMedium: index = 1
            case .systemLarge: index = 2
            case .systemExtraLarge: return nil
            case .accessoryCircular: index = 3
            case .accessoryRectangular: index = 4
            case .accessoryInline: index = 5
            }
            return Resolved(size: row[index], cornerRadius: cornerRadius(family), margins: margins(family), fromTable: exact)
        case .pad:
            let (row, exact) = nearest(padTable, screen)
            switch family {
            case .systemSmall: return Resolved(size: row[0], cornerRadius: cornerRadius(family), margins: margins(family), fromTable: exact)
            case .systemMedium: return Resolved(size: row[1], cornerRadius: cornerRadius(family), margins: margins(family), fromTable: exact)
            case .systemLarge: return Resolved(size: row[2], cornerRadius: cornerRadius(family), margins: margins(family), fromTable: exact)
            case .systemExtraLarge: return Resolved(size: row[3], cornerRadius: cornerRadius(family), margins: margins(family), fromTable: exact)
            // The HIG has no iPad accessory sizes; the 393pt iPhone values are used (estimate).
            case .accessoryCircular: return Resolved(size: CGSize(width: 72, height: 72), cornerRadius: 0, margins: EdgeInsets(), fromTable: false)
            case .accessoryRectangular: return Resolved(size: CGSize(width: 160, height: 72), cornerRadius: cornerRadius(family), margins: EdgeInsets(), fromTable: false)
            case .accessoryInline: return Resolved(size: CGSize(width: 234, height: 26), cornerRadius: 0, margins: EdgeInsets(), fromTable: false)
            }
        }
    }

    /// Apple does not publish the widget corner radius. 22pt matches Home Screen widgets on
    /// current iPhones (estimate); the rectangular accessory's background shape uses 11pt (estimate).
    static func cornerRadius(_ family: _WidgetFamilyID) -> CGFloat {
        switch family {
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge: return 22
        case .accessoryRectangular: return 11
        case .accessoryCircular, .accessoryInline: return 0
        }
    }

    /// The HIG's standard margin: "16 points for most widgets". Accessory widgets have none.
    static func margins(_ family: _WidgetFamilyID) -> EdgeInsets {
        family._isAccessory ? EdgeInsets() : EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    }

    /// The tint the accented mode uses for the accent group (a user's Home Screen tint; any
    /// value is a guess, this is a light blue).
    static let accentTint = RGBA(0.62, 0.80, 1.0)

    /// Behind accessory widgets and Live Activities, so light content is visible.
    static func backdrop(_ scheme: ColorScheme) -> RGBA {
        scheme == .dark ? RGBA(hex: 0x2B2F38) : RGBA(hex: 0x6C7686)
    }
}

/// Public helpers WidgetKit calls.
@MainActor
public enum _WidgetHost {
    /// The device the render is for: the runtime's, else the `--device` on the command line.
    static var device: DeviceProfile {
        if let runtime = Runtime.current { return runtime.config.device }
        if let name = _WidgetHostOptions.current.deviceName, let device = DeviceProfile.lookup(name) { return device }
        return DeviceProfile.all["iphone-16"]!
    }

    /// The size a family is displayed at on the selected device (TimelineProviderContext.displaySize).
    public static func displaySize(for family: _WidgetFamilyID) -> CGSize {
        WidgetMetrics.resolve(family, device: device)?.size ?? .zero
    }

    /// Whether the selected device shows this family (extra large is iPad only).
    public static func supports(_ family: _WidgetFamilyID) -> Bool {
        WidgetMetrics.resolve(family, device: device) != nil
    }

    /// "Now" for date text and timers while this entry is drawn: WidgetKit shows an entry from its date on.
    public static func setReferenceDate(_ date: Date) { Runtime.referenceDate = date }

    public static func warn(_ message: String) { Runtime.current?.warn(message) }
}

// MARK: - Container background

/// Where `containerBackground(_:for:)` puts its background. WidgetKit adds `.widget`.
public struct ContainerBackgroundPlacement: Hashable, Sendable {
    let id: String
    public static let _widget = ContainerBackgroundPlacement(id: "widget")
    /// The background of a tab view's page (watchOS), a navigation stack and a split view's columns:
    /// drawn behind the view, filling the screen.
    public static let tabView = ContainerBackgroundPlacement(id: "tabView")
    public static let navigation = ContainerBackgroundPlacement(id: "navigation")
    public static let navigationSplitView = ContainerBackgroundPlacement(id: "navigationSplitView")
}

enum TabContainerBackgroundKey: PreferenceKey {
    static let defaultValue: AnyView? = nil
    static func reduce(value: inout AnyView?, nextValue: () -> AnyView?) { value = value ?? nextValue() }
}

enum WidgetContainerBackgroundKey: PreferenceKey {
    static let defaultValue: AnyView? = nil
    static func reduce(value: inout AnyView?, nextValue: () -> AnyView?) { value = value ?? nextValue() }
}

extension View {
    public func containerBackground<S: ShapeStyle>(_ style: S, for container: ContainerBackgroundPlacement) -> some View {
        containerBackground(for: container) { Rectangle().fill(style) }
    }
    public func containerBackground<V: View>(for container: ContainerBackgroundPlacement, alignment: Alignment = .center,
                                             @ViewBuilder content: () -> V) -> some View {
        let background = AnyView(ZStack(alignment: alignment) { content() })
        if container == ._widget {
            return AnyView(preference(key: WidgetContainerBackgroundKey.self, value: background))
        }
        if container == .tabView {
            // Read by the paging tab view, which draws it behind the whole page (Chrome/TabView.swift).
            return AnyView(preference(key: TabContainerBackgroundKey.self, value: background))
        }
        return AnyView(self.background { background.ignoresSafeArea() })
    }

    /// WidgetKit's `widgetAccentable(_:)`: marks content drawn in the accent color in the accented rendering mode.
    public func _widgetAccentable(_ accentable: Bool) -> some View {
        modifier(WidgetAccentableModifier(accentable: accentable))
    }

    /// Content that may show stale data (dimmed while a widget reloads). Static frames draw it as is.
    public func invalidatableContent(_ invalidatable: Bool = true) -> some View { self }
}

// MARK: - Accented rendering

/// Accented widgets are drawn twice: once with the accent group left out (tinted white), once
/// with only the accent group (tinted with the accent color). Painter state carries the pass.
enum WidgetPass { case base, accent }

struct WidgetAccentableModifier: ViewModifier, NodeModifier {
    let accentable: Bool
    func makeNode(child: Node, _ ctx: ResolveContext) -> Node { WidgetAccentableNode(child: child, accentable: accentable) }
}

final class WidgetAccentableNode: WrapperNode {
    let accentable: Bool
    init(child: Node, accentable: Bool) {
        self.accentable = accentable
        super.init(child: child)
    }
    override func drawContent(_ p: Painter) {
        switch p.widgetPass {
        case nil: drawChildren(p)
        case .base?:
            if !accentable { drawChildren(p) }
        case .accent?:
            let saved = p.suppressesDrawing
            p.suppressesDrawing = !accentable
            drawChildren(p)
            p.suppressesDrawing = saved
        }
    }
}

enum WidgetFilters {
    /// Keeps coverage, replaces the color (unpremultiplied matrix).
    static func solid(_ c: RGBA) -> OpaquePointer? {
        Painter.colorMatrixFilter([0, 0, 0, 0, Float(c.r), 0, 0, 0, 0, Float(c.g), 0, 0, 0, 0, Float(c.b), 0, 0, 0, Float(c.a), 0])
    }
    /// Vibrant: luminance (times alpha) becomes the opacity of white, boosted so mid grays stay legible.
    static func vibrant() -> OpaquePointer? {
        let luma = sk_colorfilter_new_luma_color()
        let boost = Painter.colorMatrixFilter([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1.35, 0])
        let white = sk_colorfilter_new_mode(Painter.skColor(.white), SRCIN_SK_BLENDMODE)
        let inner = sk_colorfilter_new_compose(boost, luma)
        let result = sk_colorfilter_new_compose(white, inner)
        sk_colorfilter_unref(luma); sk_colorfilter_unref(boost); sk_colorfilter_unref(white); sk_colorfilter_unref(inner)
        return result
    }
}

// MARK: - Canvas

/// A view that draws an already resolved node.
struct ResolvedNodeView: View, PrimitiveView {
    typealias Body = Never
    let node: Node
    func resolve(_ ctx: ResolveContext, into out: inout [Node]) { out.append(node) }
}

/// Draws a widget the way the system hosts it.
public struct _WidgetCanvas: View, PrimitiveView {
    public typealias Body = Never
    let family: _WidgetFamilyID
    let renderingMode: _WidgetRenderingModeID?
    let contentMarginsDisabled: Bool
    let backgroundRemovable: Bool
    let content: @MainActor () -> AnyView

    public init(family: _WidgetFamilyID, renderingMode: _WidgetRenderingModeID?, contentMarginsDisabled: Bool,
                backgroundRemovable: Bool, content: @escaping @MainActor () -> AnyView) {
        self.family = family
        self.renderingMode = renderingMode
        self.contentMarginsDisabled = contentMarginsDisabled
        self.backgroundRemovable = backgroundRemovable
        self.content = content
    }

    func resolve(_ ctx: ResolveContext, into out: inout [Node]) {
        let device = ctx.runtime.config.device
        guard let metrics = WidgetMetrics.resolve(family, device: device) else {
            ctx.runtime.warn("\(family.rawValue) widgets are not shown on \(device.name)")
            resolveView(Text("\(family.rawValue) is not available on \(device.name)").padding(), ctx, into: &out)
            return
        }
        let mode = renderingMode ?? (family._isAccessory ? .vibrant : .fullColor)
        let margins = contentMarginsDisabled ? EdgeInsets() : metrics.margins
        let radius = metrics.cornerRadius
        let defaultMargins = family._isAccessory ? EdgeInsets() : metrics.margins
        let showsBackground = mode != .vibrant && !family._isAccessory

        // Lock Screen (vibrant) content is drawn against a dark wallpaper: it uses the dark appearance.
        let scheme = mode == .vibrant ? ColorScheme.dark : ctx.env.colorScheme
        let contentCtx = ctx.child("widget-content").with {
            $0._widgetFamily = family
            $0._widgetRenderingMode = mode
            $0._showsWidgetContainerBackground = showsBackground
            $0._widgetContentMargins = defaultMargins
            $0.colorScheme = scheme
        }
        // ContainerRelativeShape follows the widget's corner, concentric with the content margins.
        let savedRadius = ContainerRelativeShape.contextRadius
        ContainerRelativeShape.contextRadius = family == .accessoryCircular ? .infinity
            : max(0, radius - min(margins.top, margins.leading))
        let contentNode = resolveSingle(content(), contentCtx)
        ContainerRelativeShape.contextRadius = savedRadius

        let background = contentNode.preferences[WidgetContainerBackgroundKey.self]
        if background == nil, showsBackground, mode == .fullColor {
            ctx.runtime.warn("The widget has no containerBackground(for: .widget). iOS 17 and later show \"Please adopt containerBackground API\" instead of its content; the system background is drawn here.")
        }

        let size = metrics.size
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let content = ResolvedNodeView(node: contentNode)
            .padding(margins)
            .frame(width: size.width, height: size.height)
        let backgroundCtx = ctx.child("widget-background").with {
            $0._widgetFamily = family
            $0.colorScheme = scheme
        }

        let composed: AnyView
        switch mode {
        case .fullColor:
            let bg = showsBackground ? (background ?? AnyView(Color(SystemColor.background))) : AnyView(Color.clear)
            composed = AnyView(ZStack { bg.frame(width: size.width, height: size.height); content }
                .frame(width: size.width, height: size.height)
                .clipShape(shape))
        case .accented:
            let tint = WidgetMetrics.accentTint
            let base = RGBA.white.mix(tint, 0.25)
            let accentedContent = content.effect { p, _, draw in
                p.widgetPass = .base
                p.saveLayer(.init(colorFilter: WidgetFilters.solid(base)))
                draw()
                p.restore()
                p.widgetPass = .accent
                p.suppressesDrawing = true
                p.saveLayer(.init(colorFilter: WidgetFilters.solid(tint)))
                draw()
                p.restore()
                p.suppressesDrawing = false
                p.widgetPass = nil
            }
            // A removable background is replaced by the system's tinted backing; a non-removable
            // one is kept, desaturated and tinted.
            let bg: AnyView
            if backgroundRemovable || background == nil {
                bg = AnyView(Color(RGBA.black.mix(tint, 0.22)))
            } else {
                bg = AnyView(background!.grayscale(1).colorMultiply(Color(RGBA.white.mix(tint, 0.5))).brightness(-0.35))
            }
            composed = AnyView(ZStack { bg.frame(width: size.width, height: size.height); accentedContent }
                .frame(width: size.width, height: size.height)
                .clipShape(shape))
        case .vibrant:
            let vibrantContent = content.layer { _, _ in .init(colorFilter: WidgetFilters.vibrant()) }
            let clipped: AnyView = family._isAccessory ? AnyView(vibrantContent) : AnyView(vibrantContent.clipShape(shape))
            // Drawn on a neutral backdrop (the Lock Screen wallpaper's stand-in) so white content shows.
            let pad: CGFloat = 10
            composed = AnyView(clipped
                .padding(pad)
                .background(Color(WidgetMetrics.backdrop(ctx.env.colorScheme))))
        }
        resolveView(composed, backgroundCtx, into: &out)
    }
}
