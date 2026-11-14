internal import CSkia
import Foundation
import Combine

// ImageRenderer: draws a view with this engine into an offscreen bitmap. The result is usable as
// `Image(uiImage:)` / `Image(decorative: cgImage, scale:)`, which draw those pixels.

/// Pixels produced by an ImageRenderer, with the scale they were rendered at.
final class RenderedImage: Equatable, @unchecked Sendable {
    let bitmap: Bitmap
    let scale: CGFloat
    let pixelWidth: Int
    let pixelHeight: Int
    init(bitmap: Bitmap, scale: CGFloat, pixelWidth: Int, pixelHeight: Int) {
        self.bitmap = bitmap
        self.scale = scale
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
    static func == (a: RenderedImage, b: RenderedImage) -> Bool { a === b }
}

/// A bitmap made by `ImageRenderer.cgImage`. Only what a rendered image needs: its pixel size, and
/// drawing through `Image(decorative:scale:)`, `Image(_:scale:label:)` or `UIImage(cgImage:)`.
public final class CGImage: @unchecked Sendable {
    let rendered: RenderedImage
    init(rendered: RenderedImage) { self.rendered = rendered }
    public var width: Int { rendered.pixelWidth }
    public var height: Int { rendered.pixelHeight }
}

/// Stand-in for the Core Graphics drawing context, which does not exist here
/// (see `ImageRenderer.render(rasterizationScale:renderer:)`).
public final class CGContext {
    init() {}
}

extension Image {
    /// `scale` is how many pixels of the image make one point.
    public init(decorative cgImage: CGImage, scale: CGFloat, orientation: Image.Orientation = .up) {
        self.init("")
        source = .rendered(cgImage.rendered.rescaled(to: scale))
        isDecorative = true
    }
    public init(_ cgImage: CGImage, scale: CGFloat, orientation: Image.Orientation = .up, label: Text) {
        self.init("")
        source = .rendered(cgImage.rendered.rescaled(to: scale))
        accessibilityLabelText = label.plainString
    }
}

extension RenderedImage {
    /// The same pixels read at another scale (points = pixels / scale).
    func rescaled(to newScale: CGFloat) -> RenderedImage {
        guard newScale > 0, newScale != scale else { return self }
        sk_image_ref(bitmap.image)
        let size = CGSize(width: CGFloat(pixelWidth) / newScale, height: CGFloat(pixelHeight) / newScale)
        return RenderedImage(bitmap: Bitmap(image: bitmap.image, pointSize: size), scale: newScale, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }
}

extension UIImage {
    public convenience init(cgImage: CGImage) { self.init(source: .rendered(cgImage.rendered.rescaled(to: 1))) }
    public convenience init(cgImage: CGImage, scale: CGFloat, orientation: Image.Orientation) {
        self.init(source: .rendered(cgImage.rendered.rescaled(to: scale)))
    }
    public var cgImage: CGImage? {
        if case .rendered(let rendered) = source { return CGImage(rendered: rendered) }
        return nil
    }
}

@MainActor
public final class ImageRenderer<Content: View>: ObservableObject {
    public var content: Content
    /// The size proposed to the content; unspecified by default, so the content takes its ideal size.
    public var proposedSize = ProposedViewSize.unspecified
    /// Pixels per point of the image. 1 by default, as in SwiftUI.
    public var scale: CGFloat = 1
    public var isOpaque = false
    public var colorMode = ColorRenderingMode.nonLinear
    public var isObservationEnabled = false
    /// Everything is rendered in standard dynamic range.
    public var allowedDynamicRange: Image.DynamicRange?
    public let objectWillChange = PassthroughSubject<Void, Never>()

    public init(content view: Content) { content = view }

    public var uiImage: UIImage? {
        rendered(scale: scale).map { UIImage(source: .rendered($0)) }
    }
    public var cgImage: CGImage? {
        rendered(scale: scale).map { CGImage(rendered: $0) }
    }

    /// There is no Core Graphics context here to draw into (a PDF or bitmap context made by the caller),
    /// so the callback gets the content's size and a drawing function that draws nothing and warns.
    public func render(rasterizationScale: CGFloat = 1, renderer: (CGSize, (CGContext) -> Void) -> Void) {
        let size = measured()
        renderer(size) { _ in
            Runtime.current?.warn("ImageRenderer.render(rasterizationScale:renderer:) draws into a Core Graphics context, which this renderer does not have; nothing was drawn. Use uiImage or cgImage")
        }
    }

    private func measured() -> CGSize {
        _OffscreenRender.run(content, proposal: proposedSize, scale: scale, opaque: isOpaque, draw: false)?.size ?? .zero
    }

    private func rendered(scale: CGFloat) -> RenderedImage? {
        _OffscreenRender.run(content, proposal: proposedSize, scale: scale, opaque: isOpaque, draw: true)?.image
    }
}

/// A complete resolve, layout and draw of a view into its own bitmap, independent of the frame being rendered:
/// its own state store and passes, and the default environment (an ImageRenderer does not inherit the
/// environment of the view that creates it; set what the content needs on the content).
@MainActor
enum _OffscreenRender {
    static func run<V: View>(_ view: V, proposal: ProposedViewSize, scale: CGFloat, opaque: Bool, draw: Bool) -> (size: CGSize, image: RenderedImage?)? {
        let outer = Runtime.current
        let config = outer?.config ?? RenderConfiguration()
        let runtime = Runtime(config: config)
        Runtime.current = runtime
        defer {
            Runtime.current = outer
            for warning in runtime.warnings { outer?.warn(warning) }
        }
        let scale = scale > 0 ? scale : 1
        var env = EnvironmentValues()
        env.displayScale = scale
        env.platformVersion = config.osVersion
        env.renderPlatform = config.platform

        var root = Node()
        var size = CGSize.zero
        for _ in 0..<6 {
            runtime.needsAnotherPass = false
            runtime.pendingActions = []
            runtime.postLayoutActions = []
            runtime.activations.reset()
            root = resolveSingle(view, ResolveContext(env: env, path: IdentityPath(), runtime: runtime))
            size = root.sizeThatFits(proposal)
            size = CGSize(width: ceil(size.width * scale) / scale, height: ceil(size.height * scale) / scale)
            let container = CGRect(origin: .zero, size: size)
            root.place(at: .zero, size: size, PlaceContext(origin: .zero, container: container, safeRect: container, scale: scale))
            let postLayout = runtime.postLayoutActions
            runtime.postLayoutActions = []
            for action in postLayout { action() }
            let actions = runtime.pendingActions
            runtime.pendingActions = []
            for action in actions { action() }
            runtime.drainTasks()
            if actions.isEmpty && !runtime.needsAnotherPass { break }
        }
        guard draw else { return (size, nil) }

        let pixelWidth = Int((size.width * scale).rounded()), pixelHeight = Int((size.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        guard pixelWidth <= 16384, pixelHeight <= 16384 else {
            runtime.warn("ImageRenderer: the content wants to be \(Int(size.width))x\(Int(size.height)) points, too large to render; give it a frame or a proposedSize")
            return nil
        }
        var info = sk_imageinfo_t(colorspace: sk_colorspace_new_srgb(), width: Int32(pixelWidth), height: Int32(pixelHeight),
                                  colorType: RGBA_8888_SK_COLORTYPE, alphaType: PREMUL_SK_ALPHATYPE)
        guard let surface = sk_surface_new_raster(&info, 0, nil), let canvas = sk_surface_get_canvas(surface) else { return nil }
        defer { sk_surface_unref(surface) }
        let painter = Painter(canvas: canvas, scale: scale, surface: surface)
        painter.scale(scale, scale)
        sk_canvas_clear(canvas, Painter.skColor(opaque ? RGBA.black : RGBA.clear))
        root.draw(painter)
        guard let image = sk_surface_new_image_snapshot(surface) else { return nil }
        let bitmap = Bitmap(image: image, pointSize: size)
        return (size, RenderedImage(bitmap: bitmap, scale: scale, pixelWidth: pixelWidth, pixelHeight: pixelHeight))
    }
}

extension Image {
    /// How much of an image's high dynamic range is shown. A PNG frame is standard range, so this changes nothing.
    public struct DynamicRange: Hashable, Sendable {
        let raw: Int
        public static let standard = DynamicRange(raw: 0)
        public static let constrainedHigh = DynamicRange(raw: 1)
        public static let high = DynamicRange(raw: 2)
    }
    public func allowedDynamicRange(_ range: DynamicRange?) -> Image { self }
}

extension View {
    public func allowedDynamicRange(_ range: Image.DynamicRange?) -> some View { self }
}
