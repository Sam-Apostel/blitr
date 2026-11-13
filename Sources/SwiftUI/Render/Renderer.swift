internal import CSkia

// Entry point of a render: View -> node tree -> layout -> pixels -> PNG.

struct DeviceProfile {
    var name: String
    var size: CGSize
    var safeArea: EdgeInsets
    var scale: CGFloat
    var cornerRadius: CGFloat

    static let all: [String: DeviceProfile] = [
        "iphone-se": DeviceProfile(name: "iPhone SE", size: CGSize(width: 375, height: 667), safeArea: EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0), scale: 2, cornerRadius: 0),
        "iphone-16": DeviceProfile(name: "iPhone 16", size: CGSize(width: 393, height: 852), safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0), scale: 3, cornerRadius: 55),
        "iphone-16-plus": DeviceProfile(name: "iPhone 16 Plus", size: CGSize(width: 430, height: 932), safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0), scale: 3, cornerRadius: 55),
        "iphone-16-pro": DeviceProfile(name: "iPhone 16 Pro", size: CGSize(width: 402, height: 874), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), scale: 3, cornerRadius: 62),
        "iphone-16-pro-max": DeviceProfile(name: "iPhone 16 Pro Max", size: CGSize(width: 440, height: 956), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), scale: 3, cornerRadius: 62),
        "iphone-17": DeviceProfile(name: "iPhone 17", size: CGSize(width: 402, height: 874), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), scale: 3, cornerRadius: 62),
        "iphone-17-pro": DeviceProfile(name: "iPhone 17 Pro", size: CGSize(width: 402, height: 874), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), scale: 3, cornerRadius: 62),
        "iphone-17-pro-max": DeviceProfile(name: "iPhone 17 Pro Max", size: CGSize(width: 440, height: 956), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), scale: 3, cornerRadius: 62),
        "ipad": DeviceProfile(name: "iPad (11th generation)", size: CGSize(width: 820, height: 1180), safeArea: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0), scale: 2, cornerRadius: 18),
        "ipad-pro-11": DeviceProfile(name: "iPad Pro 11-inch", size: CGSize(width: 834, height: 1210), safeArea: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0), scale: 2, cornerRadius: 18),
    ]
}

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
    var background: RGBA?
    var fontDirectories: [String] = []
    var assetDirectories: [String] = []
    var padding: CGFloat = 0
    var locale: String?
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

        var canvasSize = CGSize.zero
        var root: Node = Node()
        var container = CGRect.zero, safeRect = CGRect.zero

        // State changed by onAppear & co. only shows up in a later pass, so iterate until quiet.
        for _ in 0..<6 {
            runtime.needsAnotherPass = false
            runtime.pendingActions = []
            let ctx = ResolveContext(env: env, path: IdentityPath(), runtime: runtime)
            root = resolveSingle(view, ctx)

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

            let actions = runtime.pendingActions
            runtime.pendingActions = []
            for action in actions { action() }
            if !runtime.needsAnotherPass { break }
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

        let background = config.background ?? (config.layout == .sizeThatFits ? RGBA.clear : SystemColor.background.resolve(config.colorScheme))
        sk_canvas_clear(canvas, Painter.skColor(background))
        let painter = Painter(canvas: canvas, scale: scale)
        painter.scale(scale, scale)
        root.draw(painter)
        if config.layout == .device, config.showsDeviceChrome, safeRect != container {
            DeviceChrome.draw(painter, device: config.device, size: canvasSize, scheme: root.preferences[StatusBarSchemeKey.self] ?? config.colorScheme)
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

/// The parts of the screen iOS draws itself: status bar and home indicator.
@MainActor
enum DeviceChrome {
    static func draw(_ p: Painter, device: DeviceProfile, size: CGSize, scheme: ColorScheme) {
        let color = _Paint.color(scheme == .dark ? .white : .black)
        if device.safeArea.bottom > 0 {
            let bar = CGRect(x: (size.width - 139) / 2, y: size.height - 8 - 5, width: 139, height: 5)
            p.fill(Path(roundedRect: bar, cornerRadius: 2.5, style: .circular), with: color, in: bar)
        }
        guard device.safeArea.top > 0 else { return }
        let island = device.safeArea.top >= 50
        let centerY: CGFloat = island ? device.safeArea.top - 27 : device.safeArea.top / 2
        var env = EnvironmentValues()
        env.colorScheme = scheme
        env.foregroundStyle = AnyShapeStyle(scheme == .dark ? Color.white : Color.black)
        let time = Text("9:41").font(.system(size: island ? 17 : 15, weight: .semibold)).makeNode(env)
        let timeSize = time.sizeThatFits(.unspecified)
        let leftCenter: CGFloat = island ? size.width * 0.19 : 40
        let ctx = PlaceContext(origin: .zero, container: CGRect(origin: .zero, size: size), safeRect: CGRect(origin: .zero, size: size), scale: p.scale)
        time.place(at: CGPoint(x: leftCenter - timeSize.width / 2, y: centerY - timeSize.height / 2), size: timeSize, ctx)
        time.draw(p)

        // Right cluster: signal bars, Wi-Fi, battery.
        let right: CGFloat = island ? size.width * 0.81 : size.width - 50
        var x = right - 38
        for i in 0..<4 {
            let h = 4.5 + CGFloat(i) * 2.5
            let bar = CGRect(x: x + CGFloat(i) * 4.5, y: centerY + 6 - h, width: 3, height: h)
            p.fill(Path(roundedRect: bar, cornerRadius: 1, style: .circular), with: color, in: bar)
        }
        x += 23
        let wifiCenter = CGPoint(x: x + 8, y: centerY + 5.5)
        for (i, r) in [CGFloat(11.5), 7.5, 3.5].enumerated() {
            var arc = Path()
            arc.addArc(center: wifiCenter, radius: r, startAngle: .degrees(-135), endAngle: .degrees(-45), clockwise: false)
            if i == 2 {
                arc.addLine(to: wifiCenter); arc.closeSubpath()
                p.fill(arc, with: color, in: .zero)
            } else {
                p.stroke(arc, with: color, style: StrokeStyle(lineWidth: 2.2, lineCap: .butt), in: .zero)
            }
        }
        x += 23
        let body = CGRect(x: x, y: centerY - 6.5, width: 25, height: 13)
        p.stroke(Path(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4, style: .continuous),
                 with: _Paint(.opacity(color.kind, 0.4)), style: StrokeStyle(lineWidth: 1), in: body)
        let fill = body.insetBy(dx: 2, dy: 2)
        p.fill(Path(roundedRect: fill, cornerRadius: 2.5, style: .continuous), with: color, in: fill)
        let cap = CGRect(x: body.maxX + 1, y: centerY - 2, width: 1.5, height: 4)
        p.fill(Path(roundedRect: cap, cornerRadius: 0.75, style: .circular), with: _Paint(.opacity(color.kind, 0.4)), in: cap)
    }
}
