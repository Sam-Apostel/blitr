internal import CSkia

// Entry point of a render: View -> node tree -> layout -> pixels -> PNG.

struct RenderConfiguration {
    enum Layout { case device, sizeThatFits, fixed }
    var layout: Layout = .device
    var device = DeviceProfile.all["iphone-16"]!
    /// Overrides the canvas size (`fixed`), or caps the proposed width (`sizeThatFits`).
    var width: CGFloat?
    var height: CGFloat?
    var scale: CGFloat?
    var colorScheme: ColorScheme = .light
    var dynamicTypeSize: DynamicTypeSize = .large
    var showsDeviceChrome = true
    /// Clip the image to the device's rounded display, corners transparent.
    var roundedCorners = false
    /// Draw the notch / Dynamic Island on top of the content.
    var showsSensorHousing = false
    var background: RGBA?
    var fontDirectories: [String] = []
    var assetDirectories: [String] = []
    var padding: CGFloat = 0
    var locale: String?
    /// Seconds async `.task` work may run before the frame is taken.
    var taskBudget: TimeInterval = 0.5
    /// Major iOS version whose look is rendered.
    var osVersion = RenderedPlatform.defaultVersion
}

struct RenderResult {
    var pixelSize: (width: Int, height: Int)
    var warnings: [String]
}

@MainActor
enum Renderer {
    static func render<V: View>(_ view: V, config: RenderConfiguration, to path: String) throws -> RenderResult {
        let runtime = Runtime(config: config)
        Runtime.current = runtime
        defer { Runtime.current = nil }
        FontLibrary.shared.directories = config.fontDirectories
        AssetCatalog.shared.directories = config.assetDirectories
        let scale = config.scale ?? config.device.scale

        var env = EnvironmentValues()
        env.colorScheme = config.colorScheme
        env.displayScale = scale
        env.dynamicTypeSize = config.dynamicTypeSize
        env.platformVersion = config.osVersion
        RenderedPlatform.current = config.osVersion
        // An app's accent color comes from the "AccentColor" asset when there is one.
        if let accent = AssetCatalog.shared.color(named: "AccentColor", scheme: config.colorScheme) {
            env.accentColor = Color(accent)
        }

        var canvasSize = CGSize.zero
        var root: Node = Node()
        var container = CGRect.zero, safeRect = CGRect.zero

        // State changed by onAppear & co. only shows up in a later pass, so iterate until quiet.
        for _ in 0..<6 {
            runtime.needsAnotherPass = false
            runtime.pendingActions = []
            runtime.postLayoutActions = []
            let ctx = ResolveContext(env: env, path: IdentityPath(), runtime: runtime)
            root = resolveSingle(view, ctx)
            // Sheets, alerts and dialogs presented anywhere in the tree are drawn above the root.
            root = PresentationHostNode.wrap(root, ctx)

            switch config.layout {
            case .device, .fixed:
                canvasSize = CGSize(width: config.width ?? config.device.size.width, height: config.height ?? config.device.size.height)
                container = CGRect(origin: .zero, size: canvasSize)
                safeRect = config.layout == .device && config.width == nil && config.height == nil
                    ? container.inset(by: config.device.safeArea) : container
                let size = root.sizeThatFits(ProposedViewSize(safeRect.size))
                let placeContext = PlaceContext(origin: .zero, container: container, safeRect: safeRect, scale: scale)
                // The root view is centered in the safe area, as in a hosting controller.
                root.place(at: CGPoint(x: safeRect.midX - size.width / 2, y: safeRect.midY - size.height / 2), size: size, placeContext)
            case .sizeThatFits:
                let size = root.sizeThatFits(ProposedViewSize(width: config.width, height: config.height))
                let pad = config.padding
                canvasSize = CGSize(width: ceil((size.width + pad * 2) * scale) / scale, height: ceil((size.height + pad * 2) * scale) / scale)
                container = CGRect(origin: .zero, size: canvasSize)
                safeRect = container
                root.place(at: CGPoint(x: pad, y: pad), size: size, PlaceContext(origin: .zero, container: container, safeRect: safeRect, scale: scale))
            }

            // `.preferredColorScheme` anywhere in the content restyles the whole screen.
            if let preferred = root.preferences[PreferredColorSchemeKey.self], preferred != env.colorScheme {
                env.colorScheme = preferred
                continue
            }
            let postLayout = runtime.postLayoutActions
            runtime.postLayoutActions = []
            for action in postLayout { action() }
            let actions = runtime.pendingActions
            runtime.pendingActions = []
            for action in actions { action() }
            runtime.drainTasks()
            // Actions may mutate reference types we cannot observe, so any action means another pass.
            if actions.isEmpty && !runtime.needsAnotherPass { break }
        }

        let pixelWidth = max(1, Int((canvasSize.width * scale).rounded())), pixelHeight = max(1, Int((canvasSize.height * scale).rounded()))
        guard pixelWidth <= 16384, pixelHeight <= 16384 else {
            throw RenderError("The view wants to be \(Int(canvasSize.width))x\(Int(canvasSize.height)) points, which is too large to render. Use the device layout or constrain it with --width/--height.")
        }
        var info = sk_imageinfo_t(colorspace: sk_colorspace_new_srgb(), width: Int32(pixelWidth), height: Int32(pixelHeight),
                                  colorType: RGBA_8888_SK_COLORTYPE, alphaType: PREMUL_SK_ALPHATYPE)
        guard let surface = sk_surface_new_raster(&info, 0, nil), let canvas = sk_surface_get_canvas(surface) else {
            throw RenderError("Could not allocate a \(pixelWidth)x\(pixelHeight) surface")
        }
        defer { sk_surface_unref(surface) }

        if config.roundedCorners, config.layout == .device, config.width == nil, config.height == nil {
            DeviceChrome.clipToDisplay(canvas: canvas, device: config.device, size: canvasSize, scale: scale)
        }
        let background = config.background ?? (config.layout == .sizeThatFits ? RGBA.clear : SystemColor.background.resolve(env.colorScheme))
        sk_canvas_clear(canvas, Painter.skColor(background))
        let painter = Painter(canvas: canvas, scale: scale, surface: surface)
        painter.scale(scale, scale)
        root.draw(painter)
        if config.layout == .device, config.showsDeviceChrome, safeRect != container {
            // The status bar can be restyled by content (a dark toolbar, a pushed-back presenter);
            // the home indicator sits over the bottom of the screen and follows the interface style.
            DeviceChrome.draw(painter, device: config.device, size: canvasSize,
                              statusBarScheme: root.preferences[StatusBarSchemeKey.self] ?? env.colorScheme,
                              homeIndicatorScheme: env.colorScheme, showsHousing: config.showsSensorHousing)
        }

        guard let image = sk_surface_new_image_snapshot(surface) else { throw RenderError("Could not snapshot the surface") }
        defer { sk_image_unref(image) }
        let pixmap = sk_pixmap_new()
        defer { sk_pixmap_destructor(pixmap) }
        guard sk_image_peek_pixels(image, pixmap) else { throw RenderError("Could not read back pixels") }
        guard let stream = sk_filewstream_new(path), sk_filewstream_is_valid(stream) else {
            throw RenderError("Could not open \(path) for writing")
        }
        var options = sk_pngencoder_options_t(fFilterFlags: ALL_SK_PNGENCODER_FILTER_FLAGS, fZLibLevel: 6, fComments: nil, fGainmap: nil, fGainmapInfo: nil)
        let ok = sk_pngencoder_encode(stream, pixmap, &options)
        sk_filewstream_destroy(stream)
        guard ok else { throw RenderError("PNG encoding failed") }
        return RenderResult(pixelSize: (pixelWidth, pixelHeight), warnings: runtime.warnings)
    }
}

struct RenderError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

/// Lets content choose the status bar's appearance (e.g. dark content over a light sheet).
enum StatusBarSchemeKey: PreferenceKey {
    static let defaultValue: ColorScheme? = nil
    static func reduce(value: inout ColorScheme?, nextValue: () -> ColorScheme?) { value = nextValue() ?? value }
}

