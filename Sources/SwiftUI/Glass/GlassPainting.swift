internal import CSkia

// Liquid Glass as a painter primitive: the backdrop is blurred, bent near the rim like a lens,
// tinted, and finished with a rim highlight and a soft shadow.

/// The tunable look of one glass variant. Values are best estimates of the system material and
/// are kept together here so they can be calibrated against reference captures.
struct GlassAppearance {
    /// Blur applied to the backdrop, in points (SwiftUI blur radius, about twice the gaussian sigma).
    var blurRadius: CGFloat
    var saturation: Float
    /// Flat color laid over the blurred backdrop.
    var tint: RGBA
    /// Width of the zone along the rim where the backdrop is bent, and how far (points).
    var lensWidth: CGFloat
    var lensStrength: CGFloat
    /// Rim highlight: opacity at the top-left and at the bottom-right of the shape.
    var highlight: (bright: Double, dim: Double)
    /// Hairline drawn just outside the shape (iOS 27 defines glass edges with a border).
    var edge: RGBA
    var shadow: (color: RGBA, radius: CGFloat, y: CGFloat)

    static func system(_ variant: Glass.Variant, scheme: ColorScheme, design: DesignLanguage) -> GlassAppearance {
        let dark = scheme == .dark
        let refined = design == .liquidGlass27
        var a = GlassAppearance(
            blurRadius: refined ? 18 : 14,
            saturation: 1.6,
            tint: dark ? RGBA(0.12, 0.12, 0.13, refined ? 0.42 : 0.5) : RGBA(1, 1, 1, refined ? 0.5 : 0.42),
            lensWidth: 9, lensStrength: 12,
            highlight: dark ? (refined ? 0.34 : 0.26, 0.06) : (refined ? 0.85 : 0.65, 0.2),
            edge: refined ? (dark ? RGBA(1, 1, 1, 0.1) : RGBA(0, 0, 0, 0.1)) : .clear,
            shadow: refined ? (RGBA(0, 0, 0, dark ? 0.3 : 0.1), 8, 2) : (RGBA(0, 0, 0, dark ? 0.36 : 0.14), 14, 4))
        if variant == .clear {
            a.blurRadius = 4
            a.tint = a.tint.opacity(0.3)
        }
        return a
    }
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
        color.rgb = mix(color.rgb, half3(tint.rgb), half(tint.a));
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
            let saturate = sk_colorfilter_new_color_matrix(Painter.saturationMatrix(a.saturation))
            let backdrop = sk_imagefilter_new_color_filter(saturate, blur, nil)
            sk_colorfilter_unref(saturate)
            sk_imagefilter_unref(blur)
            saveLayer(LayerOptions(backdropFilter: backdrop, bounds: bounds))
            let paint = makePaint(.color(a.tint), bounds: bounds)
            sk_canvas_draw_paint(canvas, paint)
            sk_paint_delete(paint)
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
        let saturate = sk_colorfilter_new_color_matrix(Painter.saturationMatrix(a.saturation))
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
