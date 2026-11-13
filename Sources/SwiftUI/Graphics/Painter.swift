internal import CSkia

/// The only place that draws: a thin layer over a Skia canvas working in points.
@MainActor
final class Painter {
    let canvas: OpaquePointer
    let scale: CGFloat

    init(canvas: OpaquePointer, scale: CGFloat) {
        self.canvas = canvas
        self.scale = scale
    }

    // MARK: State

    func save() { sk_canvas_save(canvas) }
    func restore() { sk_canvas_restore(canvas) }
    func translate(_ x: CGFloat, _ y: CGFloat) { sk_canvas_translate(canvas, Float(x), Float(y)) }
    func scale(_ x: CGFloat, _ y: CGFloat) { sk_canvas_scale(canvas, Float(x), Float(y)) }
    func rotate(_ angle: Angle) { sk_canvas_rotate_radians(canvas, Float(angle.radians)) }

    func concat(_ t: CGAffineTransform) {
        concat(matrix44: [Float(t.a), Float(t.c), 0, Float(t.tx),
                          Float(t.b), Float(t.d), 0, Float(t.ty),
                          0, 0, 1, 0,
                          0, 0, 0, 1])
    }

    /// Full 4x4 transform in row-major order (`m[row * 4 + column]`, points are column vectors),
    /// used for perspective effects. The C API's struct is laid out column-major despite its field
    /// names, hence the transposition here.
    func concat(matrix44 m: [Float]) {
        var sk = sk_matrix44_t(m00: m[0], m01: m[4], m02: m[8], m03: m[12],
                               m10: m[1], m11: m[5], m12: m[9], m13: m[13],
                               m20: m[2], m21: m[6], m22: m[10], m23: m[14],
                               m30: m[3], m31: m[7], m32: m[11], m33: m[15])
        sk_canvas_concat(canvas, &sk)
    }

    func clip(_ rect: CGRect) {
        var r = Painter.skRect(rect)
        sk_canvas_clip_rect_with_operation(canvas, &r, INTERSECT_SK_CLIPOP, true)
    }

    func clip(_ path: Path, evenOdd: Bool = false) {
        path.withSkPath(evenOdd: evenOdd) { sk_canvas_clip_path_with_operation(canvas, $0, INTERSECT_SK_CLIPOP, true) }
    }

    // MARK: Layers

    struct LayerOptions {
        var opacity: Double = 1
        var blendMode: BlendMode = .normal
        /// Applied to the layer's content when it is composited (blur, shadow, color adjustments).
        var imageFilter: OpaquePointer? = nil
        var colorFilter: OpaquePointer? = nil
        /// Applied to what is already drawn underneath (materials).
        var backdropFilter: OpaquePointer? = nil
        var bounds: CGRect? = nil
        /// Raw Skia blend mode, for compositing operations SwiftUI's BlendMode does not expose.
        var rawBlend: sk_blendmode_t? = nil
    }

    /// Opens an offscreen layer; everything drawn until the matching `restore()` is composited as one image.
    func saveLayer(_ options: LayerOptions) {
        let paint = sk_paint_new()
        defer { sk_paint_delete(paint) }
        if options.opacity < 1 {
            var color = sk_color4f_t(fR: 0, fG: 0, fB: 0, fA: Float(max(0, options.opacity)))
            sk_paint_set_color4f(paint, &color, nil)
        }
        if let raw = options.rawBlend { sk_paint_set_blendmode(paint, raw) }
        else if options.blendMode != .normal { sk_paint_set_blendmode(paint, Painter.skBlend(options.blendMode)) }
        if let f = options.imageFilter { sk_paint_set_imagefilter(paint, f); sk_imagefilter_unref(f) }
        if let f = options.colorFilter { sk_paint_set_colorfilter(paint, f); sk_colorfilter_unref(f) }
        var rect = options.bounds.map(Painter.skRect)
        withUnsafeMutablePointer(to: &rect) { rectPtr in
            let boundsPtr: UnsafeMutablePointer<sk_rect_t>? = options.bounds == nil ? nil
                : UnsafeMutableRawPointer(rectPtr).assumingMemoryBound(to: sk_rect_t.self)
            var rec = sk_canvas_savelayerrec_t(fBounds: boundsPtr, fPaint: paint, fBackdrop: options.backdropFilter,
                                               fFlags: NONE_SK_CANVAS_SAVELAYERREC_FLAGS)
            sk_canvas_save_layer_rec(canvas, &rec)
        }
        if let f = options.backdropFilter { sk_imagefilter_unref(f) }
    }

    // MARK: Filling and stroking

    func fill(_ path: Path, with paint: _Paint, in bounds: CGRect, style: FillStyle = FillStyle()) {
        draw(path, kind: paint.kind, bounds: bounds, opacity: 1, evenOdd: style.isEOFilled) { _ in }
    }

    func stroke(_ path: Path, with paint: _Paint, style: StrokeStyle, in bounds: CGRect) {
        if case .material = paint.kind {
            fill(path.strokedPath(style), with: paint, in: bounds)
            return
        }
        draw(path, kind: paint.kind, bounds: bounds, opacity: 1, evenOdd: false) { Painter.applyStroke(style, to: $0) }
    }

    private func draw(_ path: Path, kind: _Paint.Kind, bounds: CGRect, opacity: Double, evenOdd: Bool,
                      configure: (OpaquePointer) -> Void) {
        switch kind {
        case .opacity(let inner, let o):
            draw(path, kind: inner, bounds: bounds, opacity: opacity * o, evenOdd: evenOdd, configure: configure)
        case .material(let material, let scheme):
            // Blur + saturate what is behind the shape, then lay the material's tint over it.
            save()
            clip(path, evenOdd: evenOdd)
            let sigma = Float(material.blurRadius / 2 * scale)
            let blur = sk_imagefilter_new_blur(sigma, sigma, CLAMP_SK_SHADER_TILEMODE, nil, nil)
            let saturate = sk_colorfilter_new_color_matrix(Painter.saturationMatrix(1.8))
            let backdrop = sk_imagefilter_new_color_filter(saturate, blur, nil)
            sk_colorfilter_unref(saturate)
            sk_imagefilter_unref(blur)
            saveLayer(LayerOptions(opacity: opacity, backdropFilter: backdrop, bounds: path.boundingRect))
            let p = makePaint(.color(material.tint(scheme)), bounds: bounds, opacity: 1)
            sk_canvas_draw_paint(canvas, p)
            sk_paint_delete(p)
            restore()
            restore()
        default:
            let p = makePaint(kind, bounds: bounds, opacity: opacity)
            configure(p)
            path.withSkPath(evenOdd: evenOdd) { sk_canvas_draw_path(canvas, $0, p) }
            sk_paint_delete(p)
        }
    }

    /// A Skia paint for a resolved style. Gradients are positioned relative to `bounds`.
    func makePaint(_ kind: _Paint.Kind, bounds: CGRect, opacity: Double = 1) -> OpaquePointer {
        let paint = sk_paint_new()!
        sk_paint_set_antialias(paint, true)
        func set(color c: RGBA) {
            var c4 = sk_color4f_t(fR: Float(c.r), fG: Float(c.g), fB: Float(c.b), fA: Float(max(0, min(1, c.a * opacity))))
            sk_paint_set_color4f(paint, &c4, nil)
        }
        func gradient(_ stops: [GradientStop], _ make: (UnsafePointer<sk_color4f_t>, UnsafePointer<Float>, Int32) -> OpaquePointer?) {
            var sorted = stops.sorted { $0.location < $1.location }
            if sorted.isEmpty { set(color: .clear); return }
            if sorted.count == 1 { sorted.append(sorted[0]) }
            // Interpolating premultiplied avoids dark fringes when fading to `.clear`.
            let colors = sorted.map { sk_color4f_t(fR: Float($0.color.r), fG: Float($0.color.g), fB: Float($0.color.b), fA: Float($0.color.a)) }
            let positions = sorted.map { Float($0.location) }
            let shader = make(colors, positions, Int32(colors.count))
            sk_paint_set_shader(paint, shader)
            sk_shader_unref(shader)
            var c4 = sk_color4f_t(fR: 0, fG: 0, fB: 0, fA: Float(max(0, min(1, opacity))))
            sk_paint_set_color4f(paint, &c4, nil)
        }
        switch kind {
        case .color(let c):
            set(color: c)
        case .opacity(let inner, let o):
            sk_paint_delete(paint)
            return makePaint(inner, bounds: bounds, opacity: opacity * o)
        case .material(let m, let scheme):
            set(color: m.tint(scheme))
        case .linear(let stops, let start, let end):
            var pts = [Painter.skPoint(start.point(in: bounds)), Painter.skPoint(end.point(in: bounds))]
            gradient(stops) { sk_shader_new_linear_gradient_color4f(&pts, $0, nil, $1, $2, CLAMP_SK_SHADER_TILEMODE, nil) }
        case .radial(let stops, let center, let startRadius, let endRadius):
            var c = Painter.skPoint(center.point(in: bounds))
            if startRadius <= 0 {
                gradient(stops) { sk_shader_new_radial_gradient_color4f(&c, Float(max(endRadius, 0.001)), $0, nil, $1, $2, CLAMP_SK_SHADER_TILEMODE, nil) }
            } else {
                var c2 = c
                gradient(stops) {
                    sk_shader_new_two_point_conical_gradient_color4f(&c, Float(startRadius), &c2, Float(max(endRadius, startRadius + 0.001)), $0, nil, $1, $2, CLAMP_SK_SHADER_TILEMODE, nil)
                }
            }
        case .elliptical(let stops, let center, let startFraction, let endFraction):
            // A unit-circle radial gradient stretched to the bounds.
            var c = sk_point_t(x: 0, y: 0)
            let cp = center.point(in: bounds)
            var m = sk_matrix_t(scaleX: Float(bounds.width), skewX: 0, transX: Float(cp.x),
                                skewY: 0, scaleY: Float(bounds.height), transY: Float(cp.y), persp0: 0, persp1: 0, persp2: 1)
            let span = max(endFraction - startFraction, 0.0001)
            let remapped = stops.map { GradientStop(color: $0.color, location: (startFraction + $0.location * span) / max(endFraction, 0.0001)) }
            gradient(remapped) { sk_shader_new_radial_gradient_color4f(&c, Float(max(endFraction, 0.0001)), $0, nil, $1, $2, CLAMP_SK_SHADER_TILEMODE, &m) }
        case .angular(let stops, let center, let start, let end):
            var c = Painter.skPoint(center.point(in: bounds))
            gradient(stops) {
                sk_shader_new_sweep_gradient_color4f(&c, $0, nil, $1, $2, CLAMP_SK_SHADER_TILEMODE, Float(start.degrees), Float(end.degrees), nil)
            }
        }
        return paint
    }

    nonisolated static func applyStroke(_ style: StrokeStyle, to paint: OpaquePointer) {
        sk_paint_set_style(paint, STROKE_SK_PAINT_STYLE)
        sk_paint_set_stroke_width(paint, Float(style.lineWidth))
        sk_paint_set_stroke_miter(paint, Float(style.miterLimit))
        sk_paint_set_stroke_cap(paint, [BUTT_SK_STROKE_CAP, ROUND_SK_STROKE_CAP, SQUARE_SK_STROKE_CAP][Int(style.lineCap.rawValue)])
        sk_paint_set_stroke_join(paint, [MITER_SK_STROKE_JOIN, ROUND_SK_STROKE_JOIN, BEVEL_SK_STROKE_JOIN][Int(style.lineJoin.rawValue)])
        if style.dash.count >= 1 {
            var intervals = style.dash.map { Float($0) }
            if intervals.count % 2 == 1 { intervals += intervals }
            let effect = sk_path_effect_create_dash(intervals, Int32(intervals.count), Float(style.dashPhase))
            sk_paint_set_path_effect(paint, effect)
            sk_path_effect_unref(effect)
        }
    }

    // MARK: Filters

    nonisolated static func blurFilter(radius: CGFloat, scale: CGFloat) -> OpaquePointer? {
        // SwiftUI's blur radius is roughly twice the gaussian sigma. Filters work in device pixels.
        let sigma = Float(radius / 2 * scale)
        return sk_imagefilter_new_blur(sigma, sigma, DECAL_SK_SHADER_TILEMODE, nil, nil)
    }

    nonisolated static func shadowFilter(color: RGBA, radius: CGFloat, x: CGFloat, y: CGFloat, scale: CGFloat) -> OpaquePointer? {
        let sigma = Float(radius / 2 * scale)
        return sk_imagefilter_new_drop_shadow(Float(x * scale), Float(y * scale), sigma, sigma, skColor(color), nil, nil)
    }

    nonisolated static func colorMatrixFilter(_ matrix: [Float]) -> OpaquePointer? { sk_colorfilter_new_color_matrix(matrix) }

    nonisolated static func saturationMatrix(_ s: Float) -> [Float] {
        let (lr, lg, lb): (Float, Float, Float) = (0.2126, 0.7152, 0.0722)
        return [lr + (1 - lr) * s, lg - lg * s, lb - lb * s, 0, 0,
                lr - lr * s, lg + (1 - lg) * s, lb - lb * s, 0, 0,
                lr - lr * s, lg - lg * s, lb + (1 - lb) * s, 0, 0,
                0, 0, 0, 1, 0]
    }

    // MARK: Conversions

    nonisolated static func skRect(_ r: CGRect) -> sk_rect_t {
        sk_rect_t(left: Float(r.minX), top: Float(r.minY), right: Float(r.maxX), bottom: Float(r.maxY))
    }
    nonisolated static func skPoint(_ p: CGPoint) -> sk_point_t { sk_point_t(x: Float(p.x), y: Float(p.y)) }
    nonisolated static func skColor(_ c: RGBA) -> sk_color_t {
        func byte(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return (byte(c.a) << 24) | (byte(c.r) << 16) | (byte(c.g) << 8) | byte(c.b)
    }
    nonisolated static func skBlend(_ mode: BlendMode) -> sk_blendmode_t {
        switch mode {
        case .normal: return SRCOVER_SK_BLENDMODE
        case .multiply: return MULTIPLY_SK_BLENDMODE
        case .screen: return SCREEN_SK_BLENDMODE
        case .overlay: return OVERLAY_SK_BLENDMODE
        case .darken: return DARKEN_SK_BLENDMODE
        case .lighten: return LIGHTEN_SK_BLENDMODE
        case .colorDodge: return COLORDODGE_SK_BLENDMODE
        case .colorBurn: return COLORBURN_SK_BLENDMODE
        case .softLight: return SOFTLIGHT_SK_BLENDMODE
        case .hardLight: return HARDLIGHT_SK_BLENDMODE
        case .difference: return DIFFERENCE_SK_BLENDMODE
        case .exclusion: return EXCLUSION_SK_BLENDMODE
        case .hue: return HUE_SK_BLENDMODE
        case .saturation: return SATURATION_SK_BLENDMODE
        case .color: return COLOR_SK_BLENDMODE
        case .luminosity: return LUMINOSITY_SK_BLENDMODE
        case .sourceAtop: return SRCATOP_SK_BLENDMODE
        case .destinationOver: return DSTOVER_SK_BLENDMODE
        case .destinationOut: return DSTOUT_SK_BLENDMODE
        case .plusDarker: return DARKEN_SK_BLENDMODE
        case .plusLighter: return PLUS_SK_BLENDMODE
        }
    }
}
