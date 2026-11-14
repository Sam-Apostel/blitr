internal import CSkia

extension GraphicsContext.Filter {
    /// Pixels whose alpha is within `min...max` become `color`; all others become transparent.
    public static func alphaThreshold(min: Double, max: Double = 1, color: Color = Color.black) -> GraphicsContext.Filter {
        GraphicsContext.Filter { env, _ in
            let c = color.rgba(in: env)
            let on = UInt8(Swift.max(0, Swift.min(255, (c.a * 255).rounded())))
            let alpha: [UInt8] = (0..<256).map { a -> UInt8 in
                let v = Double(a) / 255
                return v >= min && v <= max ? on : 0
            }
            let identity: [UInt8] = (0..<256).map { UInt8($0) }
            let table = sk_colorfilter_new_table_argb(alpha, identity, identity, identity)
            let tint = sk_colorfilter_new_mode(Painter.skColor(RGBA(c.r, c.g, c.b, 1)), SRCIN_SK_BLENDMODE)
            let composed = sk_colorfilter_new_compose(tint, table)
            sk_colorfilter_unref(table)
            sk_colorfilter_unref(tint)
            return .init(colorFilter: composed)
        }
    }
}
