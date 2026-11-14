internal import CSkia

// The system backdrop tvOS 26 draws behind an app's window: a soft, blurred gradient (light blue at the top
// left, warm grey at the bottom), not a flat color. Views without a background of their own show it.
//
// Measured from the tvOS 26.5 simulator (Apple TV 4K, scripts/calibrate.py --platform tvos): the same
// backdrop sits behind every screen of the reference set. The grid below is that backdrop averaged over
// eight screens with their content masked out, at 16 x 9 cells of 120 pt; drawn with cubic filtering it
// matches the screenshots within about 4/255 (rmse). The dark backdrop is the light one darkened, per channel
// `dark = a * light + b` (fitted on the dark-appearance screens, rmse < 1/255).

@MainActor
enum TVBackdrop {
    static let columns = 16, rows = 9
    /// Light backdrop, sRGB, row by row from the top left (tvOS 26.5, measured).
    static let light: [UInt32] = [
        0xdeecfb, 0xddebfb, 0xddeafa, 0xdde8f9, 0xdde7f8, 0xdde6f6, 0xdee5f4, 0xdde4f4, 0xdbe4f3, 0xdde4f4, 0xdfe6f4, 0xdee5f4, 0xdee5f4, 0xe2e6f3, 0xe7e6ef, 0xe9e4eb,
        0xe3ecf8, 0xe2ebf8, 0xe1eaf7, 0xdfe8f7, 0xdfe7f6, 0xdee7f5, 0xdee5f2, 0xdee4f2, 0xdde4f2, 0xdde5f2, 0xdee4f1, 0xdee4f1, 0xdee4f0, 0xe3e4ee, 0xe8e4eb, 0xeae3e8,
        0xe5ecf7, 0xe3ebf6, 0xe1eaf5, 0xe0e9f5, 0xdfe8f4, 0xdfe7f2, 0xdfe5ef, 0xdfe3ec, 0xdee1ea, 0xdce0e8, 0xdadee6, 0xd8dbe3, 0xd7d9e1, 0xd9d9df, 0xddd9dd, 0xe0d9dc,
        0xe2ecf6, 0xe1eaf5, 0xdfe9f3, 0xdde7f2, 0xdbe3ed, 0xdbe1e9, 0xdfe1e7, 0xdedee4, 0xdcdce1, 0xd9d9de, 0xd5d6db, 0xd1d2d7, 0xceced3, 0xcfced2, 0xd3d0d3, 0xd8d3d4,
        0xdde6f1, 0xdbe4ee, 0xdae1ea, 0xd7dee6, 0xd5dadf, 0xd6d7da, 0xdbd6d7, 0xdad5d7, 0xd7d5d8, 0xd7d5d7, 0xd6d4d6, 0xd3d2d4, 0xd2d1d2, 0xd5d3d3, 0xdbd7d7, 0xdfdada,
        0xd5dae1, 0xd4d8dd, 0xd2d4d7, 0xd0d0cf, 0xcdccc8, 0xcdc9c4, 0xd0c9c4, 0xcfcac8, 0xcdcdcd, 0xd0cfcf, 0xd1d1d0, 0xd0d1d1, 0xd3d3d2, 0xdad7d5, 0xdfdad8, 0xe3ddda,
        0xd1cec9, 0xd0ccc5, 0xd0cbc1, 0xcec9be, 0xcbc6bc, 0xc7c3bb, 0xc6c2bc, 0xc6c4c0, 0xc5c7c6, 0xc7cac9, 0xc9cccb, 0xc9cdcc, 0xcecfce, 0xd4d3cf, 0xd8d5d1, 0xdbd8d2,
        0xd0c9b8, 0xcec8b8, 0xcfc8b9, 0xd0c8b9, 0xcec6b9, 0xcac4ba, 0xc6c1ba, 0xc3c0bc, 0xc0c1bf, 0xc0c3c2, 0xc1c6c5, 0xc3c8c8, 0xc7cbc9, 0xcbceca, 0xcfd0ca, 0xd1d1cb,
        0xcec7b6, 0xcbc5b6, 0xcac4b7, 0xcdc5b7, 0xd1c6b7, 0xcdc4b8, 0xc6c0b8, 0xc0bdb8, 0xbbbbb7, 0xb9bbb9, 0xbcc0be, 0xbfc5c3, 0xc2c8c5, 0xc5cac6, 0xc7ccc7, 0xc9cdc7,
    ]
    /// `dark = a * light + b` per channel (values in 0...255; measured).
    static let darkGain: (Double, Double, Double) = (0.496, 0.509, 0.503)
    static let darkOffset: (Double, Double, Double) = (-59.9, -62.0, -61.8)

    private static var cache: [ColorScheme: OpaquePointer] = [:]

    /// The backdrop's color at a cell, for tests and for chrome that samples what is behind it.
    static func cell(_ x: Int, _ y: Int, scheme: ColorScheme) -> (r: UInt8, g: UInt8, b: UInt8) {
        let v = light[min(rows - 1, max(0, y)) * columns + min(columns - 1, max(0, x))]
        var r = Double((v >> 16) & 0xff), g = Double((v >> 8) & 0xff), b = Double(v & 0xff)
        if scheme == .dark {
            r = r * darkGain.0 + darkOffset.0; g = g * darkGain.1 + darkOffset.1; b = b * darkGain.2 + darkOffset.2
        }
        func byte(_ c: Double) -> UInt8 { UInt8(max(0, min(255, c.rounded()))) }
        return (byte(r), byte(g), byte(b))
    }

    private static func image(_ scheme: ColorScheme) -> OpaquePointer? {
        if let cached = cache[scheme] { return cached }
        var pixels = [UInt8]()
        pixels.reserveCapacity(columns * rows * 4)
        for y in 0..<rows {
            for x in 0..<columns {
                let c = cell(x, y, scheme: scheme)
                pixels += [c.r, c.g, c.b, 255]
            }
        }
        var info = sk_imageinfo_t(colorspace: sk_colorspace_new_srgb(), width: Int32(columns), height: Int32(rows),
                                  colorType: RGBA_8888_SK_COLORTYPE, alphaType: UNPREMUL_SK_ALPHATYPE)
        let image = pixels.withUnsafeBytes { sk_image_new_raster_copy(&info, $0.baseAddress, columns * 4) }
        cache[scheme] = image
        return image
    }

    /// Fills `rect` (the screen) with the backdrop.
    static func draw(_ p: Painter, in rect: CGRect, scheme: ColorScheme) {
        guard let image = image(scheme) else { return }
        var dst = Painter.skRect(rect)
        // Mitchell cubic: smooth like the blurred original, no visible cell edges.
        var sampling = sk_sampling_options_t(fMaxAniso: 0, fUseCubic: true, fCubic: sk_cubic_resampler_t(fB: 1.0 / 3, fC: 1.0 / 3),
                                             fFilter: LINEAR_SK_FILTER_MODE, fMipmap: NONE_SK_MIPMAP_MODE)
        sk_canvas_draw_image_rect(p.canvas, image, nil, &dst, &sampling, nil)
    }
}
