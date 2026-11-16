internal import CSkia

// Liquid Glass as a painter primitive: the backdrop is blurred, bent near the rim like a lens,
// tinted, and finished with a rim highlight and a soft shadow.

/// The tunable look of one glass variant. Values are best estimates of the system material and
/// are kept together here so they can be calibrated against reference captures.
struct GlassAppearance {
    /// Blur applied to the backdrop, in points (SwiftUI blur radius, about twice the gaussian sigma).
    var blurRadius: CGFloat
    /// Saturation of the result (1 = unchanged), applied after the tint and `brightness`.
    var saturation: Float { didSet { response = nil } }
    /// Flat color laid over the blurred backdrop.
    var tint: RGBA { didSet { response = nil } }
    /// Added to every channel after the tint (0...1): dark glass lifts what is behind it.
    var brightness: Float = 0 { didSet { response = nil } }
    /// iOS 27 system glass: a nonlinear response to the blurred backdrop, used instead of the tint, `brightness`
    /// and `saturation` where the backdrop can be read (those stay as the closest linear fallback). Changing
    /// any of them (prominent, tinted and clear glass, sheets and alerts with their own look) drops it.
    var response: GlassResponse? = nil
    /// tvOS: saturate the backdrop before the tint (the earlier model) instead of the result.
    var saturatesBeforeTint = false
    /// Width of the zone along the rim where the backdrop is bent, and how far (points).
    var lensWidth: CGFloat
    var lensStrength: CGFloat
    /// Rim highlight: opacity at the top-left and at the bottom-right of the shape.
    var highlight: (bright: Double, dim: Double)
    /// Hairline drawn just outside the shape (iOS 27 defines glass edges with a border).
    var edge: RGBA
    var shadow: (color: RGBA, radius: CGFloat, y: CGFloat)

    /// The regular and clear system glass. measured: iOS 27.0 simulator, bar items over flat backgrounds:
    /// light glass turns white into 249, gray 241 into 243.5 and yellow (255,240,178) into (255,243,187)
    /// (61% of a 245 gray, then saturation 2.3); dark glass turns black into 31, 17 into 48 and
    /// (77,64,0) into (105,90,13). Over colourful content dark glass barely lifts what is behind it (the tab bar
    /// over the cards of GlassTabsAndSheets keeps their brightness), so it scales the backdrop down before
    /// lifting it: 76% of it, +33 brightness, then saturation 1.32 (least-squares fit of the tab bar and
    /// bottom accessory of GlassTabsAndSheets-0/1 and the flat values). Light glass has a faint
    /// shadow below it (-3 levels over ~10pt) and a dark hairline; dark glass has neither.
    /// iOS 26 dark glass is darker. measured: iOS 26.5 simulator: it turns black into 19...25, 17 into 31 and
    /// (77,64,0) into (51,43,2) (best linear fit: 45% of a 0.19 gray). iOS 26.5 light glass is whiter over flat
    /// backgrounds (white -> 253, gray 241 -> 251) but no linear fit of that also matches it over colourful
    /// content (GlassNavigation, tab bars got 2...6 points worse), so light keeps the iOS 27 values. Light iOS 26
    /// glass has no hairline but a broad, soft shadow: 7 levels darker just outside the edge, still 1...2
    /// levels 20pt away, a little more below than above. measured: iOS 26.5 simulator (06_Chat's video button
    /// over white)
    static func system(_ variant: Glass.Variant, scheme: ColorScheme, design: DesignLanguage) -> GlassAppearance {
        let dark = scheme == .dark
        if RenderedPlatform.platform == .tvOS { return tvOS(variant, dark: dark, refined: design == .liquidGlass27) }
        let is26 = design == .liquidGlass26
        var a = GlassAppearance(
            blurRadius: 14,
            saturation: dark ? (is26 ? 1 : 1.32) : 2.3,
            tint: is26 && dark ? RGBA(0.19, 0.19, 0.2, 0.45)
                : dark ? RGBA(0, 0, 0, 0.24) : RGBA(0.961, 0.961, 0.961, 0.607),
            brightness: !is26 && dark ? 0.129 : 0,
            lensWidth: 9, lensStrength: 12,
            highlight: dark ? (0.3, 0.1) : (0.85, 0.3),
            edge: dark ? RGBA(0, 0, 0, 0.25) : is26 ? .clear : RGBA(0, 0, 0, 0.12),
            shadow: dark ? (.clear, 0, 0) : is26 ? (RGBA(0, 0, 0, 0.07), 24, 2) : (RGBA(0, 0, 0, 0.035), 12, 6))
        if design == .liquidGlass27 {
            if dark {
                a.response = .dark27
            } else {
                // The closest linear fit (the fallback): 57% of a 250 gray, then saturation 2.0.
                a.tint = RGBA(0.98, 0.98, 0.98, 0.567)
                a.saturation = 2.0
                a.response = .light27
            }
        }
        if variant == .clear {
            a.blurRadius = 4
            a.tint = a.tint.opacity(0.3)
            a.brightness *= 0.3
            a.saturation = 1 + (a.saturation - 1) * 0.3
        }
        return a
    }
}

/// How iOS 27 system glass answers its blurred backdrop: the luma of the result is a curve of the backdrop's
/// luma (`luma.0 + luma.1 * l + luma.2 * l * l`, 0...1), and the colour around it is the backdrop's, scaled by
/// `chroma.0 + chroma.1 * l`. Fitted per pixel against the plain glass of every iOS 27.0 reference screen
/// (bars, bar items, tab bars, sheets and glass buttons, with labels, rims and misplaced content left out).
struct GlassResponse {
    var luma: (Float, Float, Float)
    var chroma: (Float, Float)

    /// Light glass lifts everything towards white and keeps most of the colour: white turns into 252, gray 241
    /// into 246, the dimmed 202 behind a sheet into 229. measured: iOS 27.0 simulator
    static let light27 = GlassResponse(luma: (0.5868, 0.3386, 0.0642), chroma: (0.8544, 0.0303))
    /// Dark glass lifts dark backdrops (black turns into 32, 17 into 48) but barely touches bright, colourful ones
    /// (a 171,150,236 card stays near 153,133,220), and adds colour over dark ones. measured: iOS 27.0 simulator
    /// (fit: luma 0.1248 + 0.9741 l - 0.382 l², colour 1.1309 - 0.2249 l). Kept 20% of the way towards the
    /// earlier linear model (76% + 33 levels, saturation 1.32): over blurred text near the rim, which our lens
    /// smears more than the system's, the full fit made NavigationTabs-Tabs worse.
    static let dark27 = GlassResponse(luma: (0.1256, 0.9313, -0.3056), chroma: (1.1053, -0.1799))
}

extension GlassAppearance {
    /// tvOS keeps the earlier estimate (focused platters); the iOS captures do not apply to it.
    static func tvOS(_ variant: Glass.Variant, dark: Bool, refined: Bool) -> GlassAppearance {
        var a = GlassAppearance(
            blurRadius: refined ? 18 : 14,
            saturation: 1.6,
            tint: dark ? RGBA(0.12, 0.12, 0.13, refined ? 0.42 : 0.5) : RGBA(1, 1, 1, refined ? 0.5 : 0.42),
            lensWidth: 9, lensStrength: 12,
            highlight: dark ? (refined ? 0.34 : 0.26, 0.06) : (refined ? 0.85 : 0.65, 0.2),
            edge: refined ? (dark ? RGBA(1, 1, 1, 0.1) : RGBA(0, 0, 0, 0.1)) : .clear,
            shadow: refined ? (RGBA(0, 0, 0, dark ? 0.3 : 0.1), 8, 2) : (RGBA(0, 0, 0, dark ? 0.36 : 0.14), 14, 4))
        a.saturatesBeforeTint = true
        if dark && !refined {
            // measured: tvOS 26.5 simulator, `glassEffect(.regular, in: Capsule())` over a (14, 16, 18) page in dark:
            // (31, 32, 34), the iOS 26 dark tint (45% of a 0.19 gray); the earlier estimate gave (21, 23, 25).
            a.tint = RGBA(0.19, 0.19, 0.2, 0.45)
        }
        if variant == .clear {
            a.blurRadius = 4
            a.tint = a.tint.opacity(0.3)
        }
        return a
    }

    /// Brightness and saturation of the neutral glass; a colored tint (prominent glass) gets neither.
    var finish: (brightness: Float, saturation: Float) {
        if saturatesBeforeTint { return (0, 1) }
        let neutral = abs(tint.r - tint.g) < 0.02 && abs(tint.g - tint.b) < 0.02
        return neutral ? (brightness, saturation) : (0, 1)
    }
    /// Saturation the backdrop gets before the tint (the earlier model, kept for tvOS).
    var preSaturation: Float { saturatesBeforeTint ? saturation : 1 }
}

/// The outline glass is drawn in. Rounded rectangles (which covers capsules and circles) get the
/// full lens treatment; arbitrary paths get blur and tint only.
enum GlassOutline {
    case roundedRect(CGRect, radius: CGFloat)
    case path(Path)

    var path: Path {
        switch self {
        case .roundedRect(let rect, let radius):
            return Path(roundedRect: rect, cornerRadius: min(radius, min(rect.width, rect.height) / 2),
                        style: radius >= min(rect.width, rect.height) / 2 - 0.01 ? .circular : .continuous)
        case .path(let p): return p
        }
    }
}

extension Painter {
    private static let lensSource = """
    uniform shader backdrop;
    uniform float4 rect;     // device-space left, top, right, bottom
    uniform float4 shape;    // corner radius, lens width, lens strength, unused
    uniform float4 tint;     // straight-alpha color mixed over the backdrop
    uniform float4 origin;   // xy: where the backdrop image's (0,0) sits in device space
    uniform float4 adjust;   // x: brightness added after the tint, y: saturation of the result
    uniform float4 curve;    // xyz: luma response (constant, linear, quadratic), w: 1 when used instead of tint
    uniform float4 chroma;   // xy: colour scale (constant, per unit of luma)

    half4 main(float2 p) {
        float2 center = (rect.xy + rect.zw) * 0.5;
        float2 halfSize = (rect.zw - rect.xy) * 0.5;
        float radius = shape.x;
        float2 q = abs(p - center) - (halfSize - radius);
        // Signed distance to the rounded rectangle: negative inside.
        float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
        float2 s = sign(p - center);
        float2 n = (q.x > 0.0 && q.y > 0.0) ? normalize(q) * s
                 : (q.x > q.y ? float2(s.x, 0.0) : float2(0.0, s.y));
        // 0 in the flat interior rising to 1 at the rim; the curve makes the bend sudden, like thick glass.
        float t = clamp(1.0 + d / max(shape.y, 0.001), 0.0, 1.0);
        float bend = t * t * t;
        float2 src = p - n * bend * shape.z;
        half4 color = backdrop.eval(src - origin.xy);
        if (curve.w > 0.5) {
            float l = dot(float3(color.rgb), float3(0.2126, 0.7152, 0.0722));
            float lr = curve.x + curve.y * l + curve.z * l * l;
            float s = chroma.x + chroma.y * l;
            color.rgb = half3(clamp(lr + s * (float3(color.rgb) - l), 0.0, 1.0));
        } else {
            color.rgb = mix(color.rgb, half3(tint.rgb), half(tint.a)) + half(adjust.x);
            if (adjust.y != 1.0) {
                half luma = dot(color.rgb, half3(0.2126, 0.7152, 0.0722));
                color.rgb = clamp(mix(half3(luma), color.rgb, half(adjust.y)), 0.0, 1.0);
            }
        }
        // The bent rim catches a little extra light.
        color.rgb += half3(bend * 0.06);
        return half4(color.rgb, 1.0);
    }
    """

    private static var lensEffect: OpaquePointer? = {
        let source = sk_string_new_with_copy(lensSource, lensSource.utf8.count)
        let error = sk_string_new_empty()
        defer { sk_string_destructor(source); sk_string_destructor(error) }
        let effect = sk_runtimeeffect_make_for_shader(source, error)
        if effect == nil, let message = sk_string_get_c_str(error) {
            FileHandle.standardError.write(Data("glass shader failed to compile: \(String(cString: message))\n".utf8))
        }
        return effect
    }()

    /// Draws a glass surface. Call before drawing the content that sits on it.
    func fillGlass(_ outline: GlassOutline, appearance a: GlassAppearance) {
        let path = outline.path
        let bounds = path.boundingRect
        guard bounds.width > 0, bounds.height > 0 else { return }

        var matrix = sk_matrix44_t()
        sk_canvas_get_matrix(canvas, &matrix)
        // (The C struct is column-major: translation lives in m30/m31, skew in m01/m10.)
        let axisAligned = matrix.m01 == 0 && matrix.m10 == 0 && matrix.m03 == 0 && matrix.m13 == 0
        let lens: (rect: CGRect, radius: CGFloat)?
        if case .roundedRect(let rect, let radius) = outline { lens = (rect, min(radius, min(rect.width, rect.height) / 2)) } else { lens = nil }

        // Take the backdrop before the shadow goes down, so the shadow only shows outside the glass.
        let snapshot: OpaquePointer? = (surface != nil && !isInsideLayer && axisAligned && lens != nil)
            ? sk_surface_new_image_snapshot(surface) : nil
        defer { if let snapshot { sk_image_unref(snapshot) } }

        if a.shadow.color.a > 0 {
            let paint = makePaint(.color(a.shadow.color), bounds: bounds)
            let blur = sk_maskfilter_new_blur(NORMAL_SK_BLUR_STYLE, Float(a.shadow.radius / 2))
            sk_paint_set_maskfilter(paint, blur)
            sk_maskfilter_unref(blur)
            save()
            // Keep the shadow out of the glass itself: it would otherwise darken the fallback path.
            path.withSkPath { sk_canvas_clip_path_with_operation(canvas, $0, DIFFERENCE_SK_CLIPOP, true) }
            path.offsetBy(dx: 0, dy: a.shadow.y).withSkPath { sk_canvas_draw_path(canvas, $0, paint) }
            restore()
            sk_paint_delete(paint)
        }

        if let snapshot, let lens, let effect = Painter.lensEffect,
           drawLens(snapshot: snapshot, effect: effect, rect: lens.rect, radius: lens.radius, matrix: matrix, appearance: a) {
            // drawn
        } else {
            // No readable backdrop (inside a layer, or transformed): blur what is behind and tint it.
            save()
            clip(path)
            let sigma = Float(a.blurRadius / 2 * scale)
            let blur = sk_imagefilter_new_blur(sigma, sigma, CLAMP_SK_SHADER_TILEMODE, nil, nil)
            let saturate = sk_colorfilter_new_color_matrix(Painter.saturationMatrix(a.saturatesBeforeTint ? a.saturation : a.finish.saturation))
            let backdrop = sk_imagefilter_new_color_filter(saturate, blur, nil)
            sk_colorfilter_unref(saturate)
            sk_imagefilter_unref(blur)
            saveLayer(LayerOptions(backdropFilter: backdrop, bounds: bounds))
            let paint = makePaint(.color(a.tint), bounds: bounds)
            sk_canvas_draw_paint(canvas, paint)
            sk_paint_delete(paint)
            if a.finish.brightness > 0 {
                let lift = makePaint(.color(RGBA(1, 1, 1, Double(a.finish.brightness))), bounds: bounds)
                sk_paint_set_blendmode(lift, PLUS_SK_BLENDMODE)
                sk_canvas_draw_paint(canvas, lift)
                sk_paint_delete(lift)
            }
            restore()
            restore()
        }

        // Rim: a thin inner highlight, brightest where light from the top-left would catch it.
        let hairline = max(1 / scale, 0.75)
        let rim: Path
        if let lens {
            rim = GlassOutline.roundedRect(lens.rect.insetBy(dx: hairline / 2, dy: hairline / 2), radius: max(0, lens.radius - hairline / 2)).path
        } else {
            rim = path
        }
        let highlight = _Paint(.linear(stops: [GradientStop(color: RGBA(1, 1, 1, a.highlight.bright), location: 0),
                                               GradientStop(color: RGBA(1, 1, 1, a.highlight.dim), location: 0.5),
                                               GradientStop(color: RGBA(1, 1, 1, a.highlight.bright * 0.6), location: 1)],
                                       start: .topLeading, end: .bottomTrailing))
        stroke(rim, with: highlight, style: StrokeStyle(lineWidth: hairline), in: bounds)
        if a.edge.a > 0 {
            stroke(path, with: .color(a.edge), style: StrokeStyle(lineWidth: hairline), in: bounds)
        }
    }

    /// Draws `body` in one solid color, keeping its coverage (a vibrant label over glass).
    func drawRecolored(_ color: RGBA, _ body: () -> Void) {
        let (r, g, b) = (Float(color.r), Float(color.g), Float(color.b))
        let matrix: [Float] = [0, 0, 0, 0, r,  0, 0, 0, 0, g,  0, 0, 0, 0, b,  0, 0, 0, 1, 0]
        saveLayer(LayerOptions(colorFilter: sk_colorfilter_new_color_matrix(matrix)))
        body()
        restore()
    }

    /// The average color already drawn in a rectangle (local coordinates), read back from the surface.
    /// Nil when it cannot be read (inside a layer, transformed, or no surface).
    func averageDrawnColor(in rect: CGRect) -> RGBA? {
        guard let surface, !isInsideLayer else { return nil }
        var matrix = sk_matrix44_t()
        sk_canvas_get_matrix(canvas, &matrix)
        guard matrix.m01 == 0, matrix.m10 == 0, matrix.m03 == 0, matrix.m13 == 0, matrix.m00 > 0, matrix.m11 > 0 else { return nil }
        let device = CGRect(x: rect.minX * CGFloat(matrix.m00) + CGFloat(matrix.m30), y: rect.minY * CGFloat(matrix.m11) + CGFloat(matrix.m31),
                            width: rect.width * CGFloat(matrix.m00), height: rect.height * CGFloat(matrix.m11)).integral
        let w = Int(device.width), h = Int(device.height)
        guard w > 0, h > 0, device.minX >= 0, device.minY >= 0 else { return nil }
        var info = sk_imageinfo_t(colorspace: nil, width: Int32(w), height: Int32(h),
                                  colorType: RGBA_8888_SK_COLORTYPE, alphaType: UNPREMUL_SK_ALPHATYPE)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ok = pixels.withUnsafeMutableBytes { sk_surface_read_pixels(surface, &info, $0.baseAddress, w * 4, Int32(device.minX), Int32(device.minY)) }
        guard ok else { return nil }
        var sum = (0.0, 0.0, 0.0)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            sum.0 += Double(pixels[i]); sum.1 += Double(pixels[i + 1]); sum.2 += Double(pixels[i + 2])
        }
        let n = Double(w * h) * 255
        return RGBA(sum.0 / n, sum.1 / n, sum.2 / n, 1)
    }

    private func drawLens(snapshot: OpaquePointer, effect: OpaquePointer, rect: CGRect, radius: CGFloat,
                          matrix: sk_matrix44_t, appearance a: GlassAppearance) -> Bool {
        let (sx, sy, tx, ty) = (CGFloat(matrix.m00), CGFloat(matrix.m11), CGFloat(matrix.m30), CGFloat(matrix.m31))
        guard sx > 0, sy > 0 else { return false }
        let device = CGRect(x: rect.minX * sx + tx, y: rect.minY * sy + ty, width: rect.width * sx, height: rect.height * sy)
        let imageSize = CGSize(width: CGFloat(sk_image_get_width(snapshot)), height: CGFloat(sk_image_get_height(snapshot)))
        // The region of backdrop needed: the shape plus what the lens can reach.
        let reach = a.lensStrength * sx + 2
        let region = device.insetBy(dx: -reach, dy: -reach).intersection(CGRect(origin: .zero, size: imageSize)).integral
        guard region.width >= 1, region.height >= 1 else { return false }

        // 1. Blur + saturate that region of the snapshot into its own image.
        var info = sk_imageinfo_t(colorspace: sk_colorspace_new_srgb(), width: Int32(region.width), height: Int32(region.height),
                                  colorType: RGBA_8888_SK_COLORTYPE, alphaType: PREMUL_SK_ALPHATYPE)
        guard let scratch = sk_surface_new_raster(&info, 0, nil), let scratchCanvas = sk_surface_get_canvas(scratch) else { return false }
        defer { sk_surface_unref(scratch) }
        let sigma = Float(a.blurRadius / 2 * sx)
        let blur = sk_imagefilter_new_blur(sigma, sigma, CLAMP_SK_SHADER_TILEMODE, nil, nil)
        let saturate = sk_colorfilter_new_color_matrix(Painter.saturationMatrix(a.preSaturation))
        let filter = sk_imagefilter_new_color_filter(saturate, blur, nil)
        sk_colorfilter_unref(saturate)
        sk_imagefilter_unref(blur)
        let blurPaint = sk_paint_new()
        sk_paint_set_imagefilter(blurPaint, filter)
        sk_imagefilter_unref(filter)
        var sampling = sk_sampling_options_t(fMaxAniso: 0, fUseCubic: false, fCubic: sk_cubic_resampler_t(fB: 0, fC: 0),
                                             fFilter: LINEAR_SK_FILTER_MODE, fMipmap: NONE_SK_MIPMAP_MODE)
        sk_canvas_draw_image(scratchCanvas, snapshot, Float(-region.minX), Float(-region.minY), &sampling, blurPaint)
        sk_paint_delete(blurPaint)
        guard let blurred = sk_surface_new_image_snapshot(scratch) else { return false }
        defer { sk_image_unref(blurred) }
        guard let backdrop = sk_image_make_shader(blurred, CLAMP_SK_SHADER_TILEMODE, CLAMP_SK_SHADER_TILEMODE, &sampling, nil) else { return false }
        defer { sk_shader_unref(backdrop) }

        // 2. Draw the shape in device space with the lens shader sampling that image.
        let uniforms: [Float] = [
            Float(device.minX), Float(device.minY), Float(device.maxX), Float(device.maxY),
            Float(radius * sx), Float(a.lensWidth * sx), Float(a.lensStrength * sx), 0,
            Float(a.tint.r), Float(a.tint.g), Float(a.tint.b), Float(a.tint.a),
            Float(region.minX), Float(region.minY), 0, 0,
            a.finish.brightness, a.finish.saturation, 0, 0,
            a.response?.luma.0 ?? 0, a.response?.luma.1 ?? 0, a.response?.luma.2 ?? 0, a.response == nil ? 0 : 1,
            a.response?.chroma.0 ?? 0, a.response?.chroma.1 ?? 0, 0, 0,
        ]
        let data = uniforms.withUnsafeBytes { sk_data_new_with_copy($0.baseAddress, $0.count) }
        defer { sk_data_unref(data) }
        var children: [OpaquePointer?] = [backdrop]
        guard let shader = children.withUnsafeMutableBufferPointer({ sk_runtimeeffect_make_shader(effect, data, $0.baseAddress, 1, nil) }) else { return false }
        defer { sk_shader_unref(shader) }
        let paint = sk_paint_new()
        defer { sk_paint_delete(paint) }
        sk_paint_set_antialias(paint, true)
        sk_paint_set_shader(paint, shader)
        save()
        sk_canvas_reset_matrix(canvas)
        GlassOutline.roundedRect(device, radius: radius * sx).path.withSkPath { sk_canvas_draw_path(canvas, $0, paint) }
        restore()
        return true
    }
}
