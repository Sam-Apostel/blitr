internal import CSkia

// Entry point of a render: View -> node tree -> layout -> pixels -> PNG.

package struct RenderConfiguration {
    enum Layout { case device, sizeThatFits, fixed }
    var layout: Layout = .device
    package var device = DeviceProfile.all["iphone-16"]!
    /// Overrides the canvas size (`fixed`), or caps the proposed width (`sizeThatFits`).
    package var width: CGFloat?
    package var height: CGFloat?
    package var scale: CGFloat?
    package var colorScheme: ColorScheme = .light
    var dynamicTypeSize: DynamicTypeSize = .large
    var showsDeviceChrome = true
    /// TipKit tips display (`--show-tips`); otherwise only after `Tips.showAllTipsForTesting()` and friends.
    package var showsTips = false
    /// Clip the image to the device's rounded display, corners transparent.
    var roundedCorners = false
    /// Draw the notch / Dynamic Island on top of the content.
    var showsSensorHousing = false
    /// Device hardware drawn around the image (`--frame`, `--frame-dir`).
    var frame: FrameRequest?
    var background: RGBA?
    var fontDirectories: [String] = []
    var assetDirectories: [String] = []
    var padding: CGFloat = 0
    /// Cut the image down to one part of the screen (`--crop`): an element's identifier or label, or `x,y,w,h` in points.
    var crop: String?
    /// Points kept around the cropped part (`--crop-padding`).
    var cropPadding: CGFloat = 0
    var locale: String?
    /// Real seconds async `.task` work may run before the frame is taken (`--task-timeout`).
    var taskTimeout: TimeInterval = 0.5
    /// Virtual seconds that pass before the frame is taken: `Task.sleep` calls ending within them
    /// return at once (`--settle-time`).
    var settleTime: TimeInterval = 2
    /// Let code reach the network. Off by default: requests fail at once, as offline.
    var allowsNetwork = false
    /// A directory of `<z>/<x>/<y>.png` map tiles drawn under maps (`--map-tiles`); nil: a placeholder surface.
    package var mapTileDirectory: String?
    /// Major OS version whose look is rendered (iOS numbering; tvOS and the others share it).
    var osVersion = RenderedPlatform.defaultVersion
    var platform = RenderPlatform.iOS
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
        _RenderClock.shared.begin(settleTime: config.settleTime)
        defer { _RenderClock.shared.end() }
        // Scripted steps and animation capture (Interaction/); nil for a plain render.
        let session = try InteractionSession.begin(runtime: runtime)
        defer { InteractionSession.end() }
        FontLibrary.shared.directories = config.fontDirectories
        AssetCatalog.shared.directories = config.assetDirectories
        let scale = config.scale ?? config.device.scale

        var env = EnvironmentValues()
        env.colorScheme = config.colorScheme
        env.displayScale = scale
        env.dynamicTypeSize = config.dynamicTypeSize
        env.platformVersion = config.osVersion
        env.renderPlatform = config.platform
        RenderedPlatform.current = config.osVersion
        RenderedPlatform.platform = config.platform
        RenderedPlatform.watchTextIsExtraLarge = config.device.idiom != .watch || config.device.portraitSize.width >= 200
        // An app's accent color comes from the "AccentColor" asset when there is one.
        if let accent = AssetCatalog.shared.color(named: "AccentColor", scheme: config.colorScheme) {
            env.accentColor = Color(accent)
        }

        var canvasSize = CGSize.zero
        var root: Node = Node()
        var container = CGRect.zero, safeRect = CGRect.zero
        // tvOS gives a screen its initial focus; elsewhere focus only moves when code or a flag asks.
        runtime.focus.automaticInitialFocus = config.platform == .tvOS
        // Focus can take a few extra passes on tvOS (focus -> isFocused -> scrolling).
        let maxPasses = config.platform == .tvOS ? 10 : 6

        // State changed by onAppear & co. only shows up in a later pass, so iterate until quiet.
        func settle() {
        for _ in 0..<maxPasses {
            runtime.needsAnotherPass = false
            runtime.pendingActions = []
            runtime.postLayoutActions = []
            runtime.activations.reset()
            session?.passWillBegin()
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
                // The views have appeared: run their onAppear and task actions, which only run once per identity.
                let actions = runtime.pendingActions
                runtime.pendingActions = []
                for action in actions { action() }
                runtime.drainTasks()
                continue
            }
            session?.passDidLayout(root)
            if runtime.focus.afterLayout(root, screen: container, runtime: runtime) { runtime.needsAnotherPass = true }
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
        }
        settle()

        // Remote simulation (Focus/RemoteSimulation.swift): a start focus, then presses, each followed by passes.
        var pressLogs: [PressLog] = []
        let focusRequest = FocusOutputs.request
        if let selector = focusRequest.focusSelector {
            let i = try runtime.focus.element(matching: selector)
            runtime.focus.requestedPath = runtime.focus.snapshot.elements[i].path
            runtime.focus.initialPath = runtime.focus.requestedPath
            settle()
        }
        for press in focusRequest.presses {
            pressLogs.append(runtime.focus.press(press, runtime: runtime))
            settle()
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

        // The frame wraps the saved images; the surface keeps the bare screen, so taps and overlays are unaffected.
        DeviceFrame.current = nil
        defer { DeviceFrame.current = nil }
        if let request = config.frame {
            if config.crop != nil {
                runtime.warn("--crop images are not framed")
            } else if config.layout != .device || config.width != nil || config.height != nil {
                runtime.warn("--frame needs the full-screen device layout; the image is not framed")
            } else {
                DeviceFrame.current = DeviceFrame.make(request, device: config.device, scale: scale,
                                                       screenPixels: (pixelWidth, pixelHeight), warn: runtime.warn)
                if DeviceFrame.current != nil, InteractionSession.request.fullContentPath != nil {
                    runtime.warn("--full-content images are not framed")
                }
            }
        }

        if config.roundedCorners, config.layout == .device, config.width == nil, config.height == nil {
            DeviceChrome.clipToDisplay(canvas: canvas, device: config.device, size: canvasSize, scale: scale)
        }
        let background = config.background ?? (config.layout == .sizeThatFits ? RGBA.clear : SystemColor.background.resolve(env.colorScheme))
        let painter = Painter(canvas: canvas, scale: scale, surface: surface)
        painter.scale(scale, scale)
        let scheme = env.colorScheme
        func drawFrame() {
            sk_canvas_clear(canvas, Painter.skColor(background))
            // tvOS 26 apps sit on the system's blurred gradient backdrop, not a flat color.
            if config.platform == .tvOS, config.background == nil, config.layout == .device,
               DesignLanguage(osVersion: config.osVersion).isGlass {
                TVBackdrop.draw(painter, in: CGRect(origin: .zero, size: canvasSize), scheme: env.colorScheme)
            }
            root.draw(painter)
            // Focus on chrome the engine made (tab items, alert buttons) has no view to carry the effect.
            if config.platform == .tvOS, let chrome = runtime.focus.focusedChromeFrame {
                FocusEffect.drawChromeHighlight(painter, rect: chrome, scheme: scheme)
            }
            if config.layout == .device, config.showsDeviceChrome, safeRect != container {
                // The status bar can be restyled by content (a dark toolbar, a pushed-back presenter);
                // the home indicator sits over the bottom of the screen and follows the interface style.
                DeviceChrome.draw(painter, device: config.device, size: canvasSize,
                                  statusBarScheme: root.preferences[StatusBarSchemeKey.self] ?? scheme,
                                  homeIndicatorScheme: scheme, osVersion: config.osVersion,
                                  showsHousing: config.showsSensorHousing)
            }
        }
        drawFrame()
        try session?.run(RenderHost(runtime: runtime, settle: settle, root: { root }, draw: drawFrame, surface: surface,
                                    canvasSize: { canvasSize }, scale: scale, colorScheme: { env.colorScheme }, environment: { env },
                                    background: background))

        guard var screen = sk_surface_new_image_snapshot(surface) else { throw RenderError("Could not snapshot the surface") }
        if let crop = config.crop {
            let rect = try Self.cropRect(crop, root: root, screen: CGRect(origin: .zero, size: canvasSize), runtime: runtime)
                .insetBy(dx: -config.cropPadding, dy: -config.cropPadding)
                .intersection(CGRect(origin: .zero, size: canvasSize))
            guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { throw RenderError("--crop \(crop): the part is not on screen") }
            var pixels = sk_irect_t(left: Int32((rect.minX * scale).rounded(.down)), top: Int32((rect.minY * scale).rounded(.down)),
                                    right: Int32((rect.maxX * scale).rounded(.up)), bottom: Int32((rect.maxY * scale).rounded(.up)))
            guard let cut = sk_image_make_subset_raster(screen, &pixels) else { throw RenderError("Could not crop the image") }
            sk_image_unref(screen)
            screen = cut
        }
        let image = try DeviceFrame.current?.compose(screen) ?? screen
        if image != screen { sk_image_unref(screen) }
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
        try AccessibilityOutputs.finish(root: root, config: config, scheme: env.colorScheme, canvasSize: canvasSize, scale: scale,
                                        painter: painter, surface: surface)
        try FocusOutputs.finish(engine: runtime.focus, config: config, canvasSize: canvasSize, scale: scale, presses: pressLogs,
                                painter: painter, surface: surface, redraw: drawFrame)
        return RenderResult(pixelSize: DeviceFrame.current?.pixelSize ?? (Int(sk_image_get_width(image)), Int(sk_image_get_height(image))),
                            warnings: runtime.warnings)
    }

    /// The part of the screen `--crop` names, in points: `x,y,w,h`, else the view with that accessibility
    /// identifier (any view, containers included), else an element by identifier or label as steps find it.
    static func cropRect(_ crop: String, root: Node, screen: CGRect, runtime: Runtime) throws -> CGRect {
        let numbers = crop.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if numbers.count == 4, crop.split(separator: ",").count == 4 {
            return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        }
        let name = crop.hasPrefix("id:") ? String(crop.dropFirst(3)) : crop
        var found: [CGRect] = []
        func visit(_ node: Node) {
            if node.ax?.info.identifier == name, node.frame.width > 0, node.frame.height > 0 {
                found.append(CGRect(origin: node.absoluteOrigin, size: node.frame.size))
            }
            for child in node.children { visit(child) }
        }
        visit(root)
        if let rect = found.first {
            if found.count > 1 { runtime.warn("--crop \(crop) matches \(found.count) views; the first is used") }
            return rect
        }
        let index = ElementIndex(root: root, screen: screen, runtime: runtime)
        return try index.resolve(.text(name, nth: nil), step: "--crop", interactiveOnly: false).frame
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

