internal import CSkia

// `--frame` and `--frame-dir`: the device's hardware drawn around the rendered screen.
//
// Apple's bezel artwork cannot be redistributed, so the generic frame is drawn here from the device
// profile: the display's size and corner radius, a black glass border, a graphite band, the side
// buttons and the Dynamic Island or notch. The proportions are estimates from the published
// dimensions (body width against screen width), not measured artwork.
//
// `--frame-dir <dir>` uses the user's own images instead: `<dir>/<device-id>.png` (and optionally
// `<device-id>-landscape.png`), a PNG whose screen is a transparent hole. The hole is the transparent
// region around the image's centre; the screen is scaled into its bounding box and the image drawn
// over it, so the frame's own rounded corners mask the screen's.

/// What `--frame` / `--frame-dir` asked for.
enum FrameRequest {
    case procedural
    case directory(String)
}

@MainActor
final class DeviceFrame {
    /// The frame of the render in progress, set by `Renderer.render` when one applies.
    static var current: DeviceFrame?

    /// Size of a framed image, in pixels.
    let pixelSize: (width: Int, height: Int)
    private let kind: Kind

    private enum Kind {
        case procedural(FrameGeometry, scale: CGFloat)
        case image(OpaquePointer, hole: CGRect)   // sk_image, hole in pixels
    }

    deinit {
        if case .image(let image, _) = kind { sk_image_unref(image) }
    }

    private init(pixelSize: (Int, Int), kind: Kind) {
        self.pixelSize = pixelSize
        self.kind = kind
    }

    /// The frame for `device`, or nil with a warning when the render cannot be framed.
    static func make(_ request: FrameRequest, device: DeviceProfile, scale: CGFloat, screenPixels: (width: Int, height: Int),
                     warn: (String) -> Void) -> DeviceFrame? {
        if case .directory(let dir) = request {
            let landscape = dir + "/" + device.id + "-landscape.png", portrait = dir + "/" + device.id + ".png"
            let fm = FileManager.default
            let rotatesPortrait = device.orientation.isLandscape && (device.idiom == .phone || device.idiom == .pad)
            if device.orientation.isLandscape, fm.fileExists(atPath: landscape) {
                return fromImage(landscape, rotation: nil, screenPixels: screenPixels, warn: warn)
            }
            if fm.fileExists(atPath: portrait) {
                return fromImage(portrait, rotation: rotatesPortrait ? device.orientation : nil, screenPixels: screenPixels, warn: warn)
            }
            warn("--frame-dir: no \(device.id).png in \(dir); the generic frame is drawn instead")
        }
        let geometry = FrameGeometry(device)
        let size = geometry.canvasSize
        return DeviceFrame(pixelSize: (Int((size.width * scale).rounded()), Int((size.height * scale).rounded())),
                           kind: .procedural(geometry, scale: scale))
    }

    /// Draws the frame around `screen` (an sk_image of the whole rendered screen); the caller unrefs the result.
    func compose(_ screen: OpaquePointer) throws -> OpaquePointer {
        var info = sk_imageinfo_t(colorspace: sk_colorspace_new_srgb(), width: Int32(pixelSize.width), height: Int32(pixelSize.height),
                                  colorType: RGBA_8888_SK_COLORTYPE, alphaType: PREMUL_SK_ALPHATYPE)
        guard let surface = sk_surface_new_raster(&info, 0, nil), let canvas = sk_surface_get_canvas(surface) else {
            throw RenderError("--frame: could not allocate a \(pixelSize.width)x\(pixelSize.height) surface")
        }
        defer { sk_surface_unref(surface) }
        sk_canvas_clear(canvas, 0)
        var sampling = sk_sampling_options_t(fMaxAniso: 0, fUseCubic: false, fCubic: sk_cubic_resampler_t(fB: 0, fC: 0),
                                             fFilter: LINEAR_SK_FILTER_MODE, fMipmap: NONE_SK_MIPMAP_MODE)
        var src = sk_rect_t(left: 0, top: 0, right: Float(sk_image_get_width(screen)), bottom: Float(sk_image_get_height(screen)))
        switch kind {
        case .procedural(let geometry, let scale):
            let p = Painter(canvas: canvas, scale: scale, surface: surface)
            p.scale(scale, scale)
            geometry.drawBehind(p)
            p.save()
            if geometry.screenRadius > 0 {
                p.clip(Path(roundedRect: geometry.screenRect, cornerRadius: geometry.screenRadius, style: .continuous))
            }
            var dst = Painter.skRect(geometry.screenRect)
            sk_canvas_draw_image_rect(canvas, screen, &src, &dst, &sampling, nil)
            p.restore()
            geometry.drawInFront(p)
        case .image(let image, let hole):
            var dst = Painter.skRect(hole)
            sk_canvas_draw_image_rect(canvas, screen, &src, &dst, &sampling, nil)
            sk_canvas_draw_image(canvas, image, 0, 0, &sampling, nil)
        }
        guard let result = sk_surface_new_image_snapshot(surface) else { throw RenderError("--frame: could not snapshot the frame") }
        return result
    }

    // MARK: User images

    private static func fromImage(_ path: String, rotation: DeviceOrientation?, screenPixels: (width: Int, height: Int),
                                  warn: (String) -> Void) -> DeviceFrame? {
        guard let data = sk_data_new_from_file(path) else { warn("--frame-dir: cannot read \(path); the image is not framed"); return nil }
        defer { sk_data_unref(data) }
        guard var image = sk_image_new_from_encoded(data) else { warn("--frame-dir: \(path) is not an image; the image is not framed"); return nil }
        if let rotation, let rotated = rotate(image, to: rotation) {
            sk_image_unref(image)
            image = rotated
        }
        let w = Int(sk_image_get_width(image)), h = Int(sk_image_get_height(image))
        var info = sk_imageinfo_t(colorspace: sk_colorspace_new_srgb(), width: Int32(w), height: Int32(h),
                                  colorType: RGBA_8888_SK_COLORTYPE, alphaType: UNPREMUL_SK_ALPHATYPE)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ok = pixels.withUnsafeMutableBytes { sk_image_read_pixels(image, &info, $0.baseAddress, w * 4, 0, 0, ALLOW_SK_IMAGE_CACHING_HINT) }
        guard ok, let hole = transparentHole(pixels, width: w, height: h) else {
            warn("--frame-dir: \(path) has no transparent screen area at its centre; the image is not framed")
            sk_image_unref(image)
            return nil
        }
        let holeAspect = hole.width / hole.height, screenAspect = CGFloat(screenPixels.width) / CGFloat(screenPixels.height)
        if abs(holeAspect / screenAspect - 1) > 0.02 {
            warn("--frame-dir: the screen hole of \(path) is \(Int(hole.width))x\(Int(hole.height)) pixels, a different shape from the \(screenPixels.width)x\(screenPixels.height) render; the screen is stretched to fit")
        }
        return DeviceFrame(pixelSize: (w, h), kind: .image(image, hole: hole))
    }

    /// The bounding box of the transparent pixels (alpha below half) connected to the image's centre.
    static func transparentHole(_ pixels: [UInt8], width w: Int, height h: Int) -> CGRect? {
        func clear(_ i: Int) -> Bool { pixels[i * 4 + 3] < 128 }
        let start = (h / 2) * w + w / 2
        guard w > 0, h > 0, clear(start) else { return nil }
        var seen = [Bool](repeating: false, count: w * h)
        var stack = [start]
        seen[start] = true
        var minX = w, minY = h, maxX = 0, maxY = 0
        while let i = stack.popLast() {
            let x = i % w, y = i / w
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < w && ny < h {
                let n = ny * w + nx
                if !seen[n], clear(n) { seen[n] = true; stack.append(n) }
            }
        }
        // A hole touching the image's edge is the background around the device, not a screen.
        guard minX > 0, minY > 0, maxX < w - 1, maxY < h - 1 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// A portrait frame image turned for a landscape render (the device's top to the left for landscape-left).
    private static func rotate(_ image: OpaquePointer, to orientation: DeviceOrientation) -> OpaquePointer? {
        let w = Int(sk_image_get_width(image)), h = Int(sk_image_get_height(image))
        var info = sk_imageinfo_t(colorspace: sk_colorspace_new_srgb(), width: Int32(h), height: Int32(w),
                                  colorType: RGBA_8888_SK_COLORTYPE, alphaType: PREMUL_SK_ALPHATYPE)
        guard let surface = sk_surface_new_raster(&info, 0, nil), let canvas = sk_surface_get_canvas(surface) else { return nil }
        defer { sk_surface_unref(surface) }
        sk_canvas_clear(canvas, 0)
        FrameGeometry.rotate(canvas, orientation, portraitWidth: CGFloat(w), portraitHeight: CGFloat(h))
        var sampling = sk_sampling_options_t(fMaxAniso: 0, fUseCubic: false, fCubic: sk_cubic_resampler_t(fB: 0, fC: 0),
                                             fFilter: NEAREST_SK_FILTER_MODE, fMipmap: NONE_SK_MIPMAP_MODE)
        sk_canvas_draw_image(canvas, image, 0, 0, &sampling, nil)
        return sk_surface_new_image_snapshot(surface)
    }
}

// MARK: - Procedural frames

/// The generic hardware of one device, in points. Phones and iPads are laid out portrait and turned
/// for landscape renders; the watch and the TV are drawn as they are.
@MainActor
struct FrameGeometry {
    enum Side { case left, right, top }
    struct Button {
        var side: Side
        /// Distance of the button's start from the body's top (left and right side) or left edge (top side).
        var start: CGFloat
        var length: CGFloat
        /// How far it stands out from the body.
        var protrusion: CGFloat
        var crown = false
    }

    let idiom: DeviceIdiom
    let orientation: DeviceOrientation
    /// The screen in portrait (phones, iPads) or as rendered (watch, TV).
    let screenSize: CGSize
    let screenRadius: CGFloat
    /// Black glass between the screen and the band, per edge of the portrait device.
    let border: EdgeInsets
    /// The metal band seen from the front.
    let band: CGFloat
    let bodyRadius: CGFloat
    let buttons: [Button]
    let housing: SensorHousing
    let homeButton: Bool
    /// Front camera for iPads: on the top edge or (landscape-camera iPads) on the right one.
    let padCamera: Side?
    /// Watch strap stubs above and below the case.
    let strap: CGFloat
    /// Transparent space around the body for buttons and the strap.
    let margin: EdgeInsets

    init(_ device: DeviceProfile) {
        idiom = device.idiom
        housing = device.housing
        homeButton = { if case .homeButton = device.housing { return true }; return false }()
        let rotates = device.idiom == .phone || device.idiom == .pad
        orientation = rotates ? device.orientation : .portrait
        screenSize = rotates ? device.portraitSize : device.size
        screenRadius = device.cornerRadius
        var buttons: [Button] = []
        var strap: CGFloat = 0
        var padCamera: Side?
        let h = screenSize.height
        switch device.idiom {
        case .phone:
            // Border plus band per side, from the published body widths against the screen widths:
            // about 14pt on the 16 Pro and 17 family, 18pt on the 14 Pro to 16, 20pt on the notch phones.
            let (glass, metal): (CGFloat, CGFloat)
            switch device.housing {
            case .dynamicIsland(_, let top) where top >= 14: (glass, metal) = (9, 5)
            case .dynamicIsland: (glass, metal) = (12, 6)
            case .notch: (glass, metal) = device.scale < 3 ? (24, 7) : (14, 6)
            case .homeButton, .none: (glass, metal) = (22, 5)
            }
            if homeButton {
                border = EdgeInsets(top: 100, leading: glass, bottom: 100, trailing: glass)
            } else {
                border = EdgeInsets(top: glass, leading: glass, bottom: glass, trailing: glass)
            }
            band = metal
            let body = h + border.top + border.bottom + metal * 2
            // Left: ring switch or Action button, volume up, volume down. Right: side button, and Camera Control.
            buttons = [Button(side: .left, start: body * 0.165, length: body * 0.04, protrusion: 2),
                       Button(side: .left, start: body * 0.245, length: body * 0.075, protrusion: 2),
                       Button(side: .left, start: body * 0.34, length: body * 0.075, protrusion: 2),
                       Button(side: .right, start: body * 0.255, length: body * 0.115, protrusion: 2)]
            let id = device.id
            if (id.hasPrefix("iphone-16") && id != "iphone-16e") || id.hasPrefix("iphone-17") || id == "iphone-air" {
                buttons.append(Button(side: .right, start: body * 0.56, length: body * 0.06, protrusion: 1))
            }
            margin = EdgeInsets(top: 0, leading: 3, bottom: 0, trailing: 3)
        case .pad:
            let glass: CGFloat = device.id.hasPrefix("ipad-pro") ? 30 : device.id == "ipad-mini" ? 34 : 40
            border = EdgeInsets(top: glass, leading: glass, bottom: glass, trailing: glass)
            band = 4
            let width = screenSize.width + glass * 2 + 8, body = h + glass * 2 + 8
            buttons = [Button(side: .top, start: width - 60 - width * 0.06, length: 60, protrusion: 1.5),
                       Button(side: .right, start: body * 0.06, length: body * 0.05, protrusion: 1.5),
                       Button(side: .right, start: body * 0.12, length: body * 0.05, protrusion: 1.5)]
            padCamera = device.id == "ipad-mini" ? .top : .right
            margin = EdgeInsets(top: 2, leading: 0, bottom: 0, trailing: 2)
        case .watch:
            border = EdgeInsets(top: 9, leading: 9, bottom: 9, trailing: 9)
            band = 12
            let body = h + 18 + 24
            let ultra = device.id.contains("ultra")
            buttons = [Button(side: .right, start: body * 0.22, length: body * 0.17, protrusion: ultra ? 10 : 8, crown: true),
                       Button(side: .right, start: body * 0.5, length: body * 0.24, protrusion: 1.5)]
            if ultra { buttons.append(Button(side: .left, start: body * 0.26, length: body * 0.2, protrusion: 2)) }
            strap = (body * 0.2).rounded()
            margin = EdgeInsets(top: strap, leading: 3, bottom: strap, trailing: 12)
        case .tv:
            border = EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
            band = 3
            margin = EdgeInsets()
        }
        self.buttons = buttons
        self.strap = strap
        self.padCamera = padCamera
        // Concentric with the display; the iPhone SE and the TV have their own.
        if homeButton { bodyRadius = 56 }
        else if device.idiom == .tv { bodyRadius = 6 }
        else { bodyRadius = screenRadius + max(border.leading, border.top) + band }
    }

    /// The portrait (unrotated) canvas.
    private var portraitCanvas: CGSize {
        CGSize(width: margin.leading + bodyRect.width + margin.trailing, height: margin.top + bodyRect.height + margin.bottom)
    }
    var canvasSize: CGSize {
        let c = portraitCanvas
        return orientation.isLandscape ? CGSize(width: c.height, height: c.width) : c
    }
    /// The device body in the portrait canvas.
    private var bodyRect: CGRect {
        CGRect(x: margin.leading, y: margin.top,
               width: screenSize.width + border.leading + border.trailing + band * 2,
               height: screenSize.height + border.top + border.bottom + band * 2)
    }
    private var portraitScreenRect: CGRect {
        CGRect(x: bodyRect.minX + band + border.leading, y: bodyRect.minY + band + border.top, width: screenSize.width, height: screenSize.height)
    }
    /// The screen in the output canvas (turned for landscape).
    var screenRect: CGRect {
        let r = portraitScreenRect, c = portraitCanvas
        switch orientation {
        case .portrait: return r
        case .landscapeLeft: return CGRect(x: r.minY, y: c.width - r.maxX, width: r.height, height: r.width)
        case .landscapeRight: return CGRect(x: c.height - r.maxY, y: r.minX, width: r.height, height: r.width)
        }
    }

    /// Turns `canvas` so portrait drawing lands in the landscape output: the device's top goes left for
    /// landscape-left, right for landscape-right.
    static func rotate(_ canvas: OpaquePointer, _ orientation: DeviceOrientation, portraitWidth: CGFloat, portraitHeight: CGFloat) {
        switch orientation {
        case .portrait: break
        case .landscapeLeft:
            sk_canvas_translate(canvas, 0, Float(portraitWidth))
            sk_canvas_rotate_radians(canvas, -Float.pi / 2)
        case .landscapeRight:
            sk_canvas_translate(canvas, Float(portraitHeight), 0)
            sk_canvas_rotate_radians(canvas, Float.pi / 2)
        }
    }

    // MARK: Colours

    private static let glass = RGBA(0.02, 0.02, 0.024)
    /// A graphite finish: lighter at the top, as if lit from above.
    private static func metal(_ rect: CGRect, vertical: Bool = true) -> _Paint {
        _Paint(.linear(stops: [GradientStop(color: RGBA(hex: 0x5A5B5F), location: 0),
                               GradientStop(color: RGBA(hex: 0x3A3B3F), location: 0.45),
                               GradientStop(color: RGBA(hex: 0x2C2D30), location: 1)],
                       start: vertical ? .top : .leading, end: vertical ? .bottom : .trailing))
    }

    // MARK: Drawing

    /// Strap, buttons, body and glass: everything under the screen.
    func drawBehind(_ p: Painter) {
        p.save()
        let c = portraitCanvas
        Self.rotate(p.canvas, orientation, portraitWidth: c.width, portraitHeight: c.height)
        let body = bodyRect
        if strap > 0 {
            let width = (body.width * 0.62).rounded()
            let x = body.midX - width / 2
            let strapColor = RGBA(hex: 0x1C1C1E)
            let upper = CGRect(x: x, y: 0, width: width, height: body.midY)
            p.fill(Path(upper), with: _Paint(.linear(stops: [GradientStop(color: strapColor.opacity(0), location: 0),
                                                              GradientStop(color: strapColor, location: 0.6)],
                                                      start: .top, end: .bottom)), in: upper)
            let lower = CGRect(x: x, y: body.midY, width: width, height: c.height - body.midY)
            p.fill(Path(lower), with: _Paint(.linear(stops: [GradientStop(color: strapColor, location: 0.4),
                                                              GradientStop(color: strapColor.opacity(0), location: 1)],
                                                      start: .top, end: .bottom)), in: lower)
        }
        for button in buttons { drawButton(p, button, body: body) }
        let outline = Path(roundedRect: body, cornerRadius: bodyRadius, style: .continuous)
        p.fill(outline, with: Self.metal(body), in: body)
        // A polished edge: a dark hairline outside, a faint highlight where the band meets the glass.
        p.stroke(Path(roundedRect: body.insetBy(dx: 0.25, dy: 0.25), cornerRadius: bodyRadius - 0.25, style: .continuous),
                 with: .color(RGBA(0, 0, 0, 0.55)), style: StrokeStyle(lineWidth: 0.5), in: body)
        let front = body.insetBy(dx: band, dy: band)
        let frontRadius = max(0, bodyRadius - band)
        p.fill(Path(roundedRect: front, cornerRadius: frontRadius, style: .continuous), with: .color(Self.glass), in: front)
        p.stroke(Path(roundedRect: front.insetBy(dx: -0.25, dy: -0.25), cornerRadius: frontRadius + 0.25, style: .continuous),
                 with: .color(RGBA(1, 1, 1, 0.12)), style: StrokeStyle(lineWidth: 0.5), in: front)
        drawBezelDetails(p)
        p.restore()
    }

    /// The Dynamic Island or notch, over the screen.
    func drawInFront(_ p: Painter) {
        let screen = portraitScreenRect
        p.save()
        let c = portraitCanvas
        Self.rotate(p.canvas, orientation, portraitWidth: c.width, portraitHeight: c.height)
        switch housing {
        case .dynamicIsland(let s, let top):
            let pill = CGRect(x: screen.midX - s.width / 2, y: screen.minY + top, width: s.width, height: s.height)
            p.fill(Path(roundedRect: pill, cornerRadius: s.height / 2, style: .continuous), with: .color(.black), in: pill)
        case .notch(let s):
            // Part of the glass border: square where it meets the border, rounded below.
            let notch = CGRect(x: screen.midX - s.width / 2, y: screen.minY - border.top, width: s.width, height: s.height + border.top)
            p.fill(Path(roundedRect: notch, cornerRadius: 20, style: .continuous), with: .color(Self.glass), in: notch)
            let joint = CGRect(x: notch.minX, y: notch.minY, width: notch.width, height: border.top + 8)
            p.fill(Path(joint), with: .color(Self.glass), in: joint)
        default: break
        }
        p.restore()
    }

    private func drawButton(_ p: Painter, _ b: Button, body: CGRect) {
        let rect: CGRect
        let inset: CGFloat = 4   // the part hidden under the body
        switch b.side {
        case .left: rect = CGRect(x: body.minX - b.protrusion, y: body.minY + b.start, width: b.protrusion + inset, height: b.length)
        case .right: rect = CGRect(x: body.maxX - inset, y: body.minY + b.start, width: b.protrusion + inset, height: b.length)
        case .top: rect = CGRect(x: body.minX + b.start, y: body.minY - b.protrusion, width: b.length, height: b.protrusion + inset)
        }
        if b.crown {
            // The Digital Crown seen side on: a ridged cylinder.
            p.fill(Path(roundedRect: rect, cornerRadius: 2.5, style: .continuous),
                   with: _Paint(.linear(stops: [GradientStop(color: RGBA(hex: 0x2A2B2E), location: 0),
                                                GradientStop(color: RGBA(hex: 0x6A6B6F), location: 0.35),
                                                GradientStop(color: RGBA(hex: 0x26272A), location: 1)],
                                        start: .top, end: .bottom)), in: rect)
            var y = rect.minY + 2
            while y < rect.maxY - 1.5 {
                let ridge = CGRect(x: body.maxX + 0.5, y: y, width: rect.maxX - body.maxX - 1.5, height: 0.5)
                p.fill(Path(ridge), with: .color(RGBA(0, 0, 0, 0.35)), in: ridge)
                y += 1.6
            }
            return
        }
        let radius = min(rect.width, rect.height) / 2
        p.fill(Path(roundedRect: rect, cornerRadius: radius, style: .circular), with: Self.metal(rect, vertical: b.side == .top), in: rect)
    }

    /// The earpiece, camera and home button of the iPhone SE, and the iPads' camera.
    private func drawBezelDetails(_ p: Painter) {
        let body = bodyRect, screen = portraitScreenRect
        if homeButton {
            let topMid = (body.minY + band + screen.minY) / 2
            let slot = CGRect(x: body.midX - 26, y: topMid - 3, width: 52, height: 6)
            p.fill(Path(roundedRect: slot, cornerRadius: 3, style: .circular), with: .color(RGBA(hex: 0x1E1F22)), in: slot)
            let camera = CGRect(x: body.midX - 4.5, y: topMid - 26, width: 9, height: 9)
            p.fill(Path(ellipseIn: camera), with: .color(RGBA(hex: 0x15161A)), in: camera)
            let bottomMid = (screen.maxY + body.maxY - band) / 2
            let button = CGRect(x: body.midX - 33, y: bottomMid - 33, width: 66, height: 66)
            p.fill(Path(ellipseIn: button), with: .color(RGBA(hex: 0x0C0C0E)), in: button)
            p.stroke(Path(ellipseIn: button.insetBy(dx: 0.75, dy: 0.75)), with: .color(RGBA(hex: 0x4A4B4F)),
                     style: StrokeStyle(lineWidth: 1.5), in: button)
        }
        if let side = padCamera {
            let center = side == .top ? CGPoint(x: body.midX, y: (body.minY + band + screen.minY) / 2)
                                      : CGPoint(x: (screen.maxX + body.maxX - band) / 2, y: body.midY)
            let lens = CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)
            p.fill(Path(ellipseIn: lens), with: .color(RGBA(hex: 0x15161B)), in: lens)
            let glint = CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3)
            p.fill(Path(ellipseIn: glint), with: .color(RGBA(hex: 0x23263A)), in: glint)
        }
    }
}
