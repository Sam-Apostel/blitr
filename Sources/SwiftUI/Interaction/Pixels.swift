internal import CSkia

// Pixel buffers of captured frames, and their way in and out of Skia.

/// One captured frame: 8-bit RGBA, not premultiplied, rows top to bottom.
final class FrameImage {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    func isIdentical(to other: FrameImage) -> Bool {
        width == other.width && height == other.height && pixels == other.pixels
    }
}

@MainActor
enum FramePixels {
    private static func info(_ width: Int, _ height: Int, premultiplied: Bool = false) -> sk_imageinfo_t {
        sk_imageinfo_t(colorspace: sk_colorspace_new_srgb(), width: Int32(width), height: Int32(height),
                       colorType: RGBA_8888_SK_COLORTYPE, alphaType: premultiplied ? PREMUL_SK_ALPHATYPE : UNPREMUL_SK_ALPHATYPE)
    }

    /// A snapshot of a rendered screen, inside the device frame when one was asked for (the caller unrefs it).
    private static func framedSnapshot(_ surface: OpaquePointer) throws -> OpaquePointer {
        guard let screen = sk_surface_new_image_snapshot(surface) else { throw RenderError("Could not snapshot the surface") }
        guard let frame = DeviceFrame.current else { return screen }
        defer { sk_image_unref(screen) }
        return try frame.compose(screen)
    }

    /// Writes what is on the surface as a PNG, encoded exactly like the main screenshot. A rendered
    /// screen (`framed`) gets the device frame when one was asked for.
    static func writePNG(surface: OpaquePointer, to path: String, framed: Bool = false) throws {
        guard let image = framed ? try framedSnapshot(surface) : sk_surface_new_image_snapshot(surface) else {
            throw RenderError("Could not snapshot the surface")
        }
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
        guard ok else { throw RenderError("PNG encoding failed for \(path)") }
    }

    /// The surface's pixels, scaled by `factor` (1 keeps them); `framed` as in `writePNG`.
    static func grab(surface: OpaquePointer, factor: Double = 1, framed: Bool = false) throws -> FrameImage {
        guard let image = framed ? try framedSnapshot(surface) : sk_surface_new_image_snapshot(surface) else {
            throw RenderError("Could not snapshot the surface")
        }
        defer { sk_image_unref(image) }
        let w = Int(sk_image_get_width(image)), h = Int(sk_image_get_height(image))
        let outW = max(1, Int((Double(w) * factor).rounded())), outH = max(1, Int((Double(h) * factor).rounded()))
        var pixels = [UInt8](repeating: 0, count: outW * outH * 4)
        var dstInfo = info(outW, outH)
        let ok: Bool = pixels.withUnsafeMutableBytes { buffer in
            if outW == w && outH == h {
                return sk_image_read_pixels(image, &dstInfo, buffer.baseAddress, outW * 4, 0, 0, ALLOW_SK_IMAGE_CACHING_HINT)
            }
            // Scale in premultiplied space (as Skia requires for filtering), then unpremultiply.
            var premul = info(outW, outH, premultiplied: true)
            guard let dst = sk_pixmap_new_with_params(&premul, buffer.baseAddress, outW * 4) else { return false }
            defer { sk_pixmap_destructor(dst) }
            var sampling = sk_sampling_options_t(fMaxAniso: 0, fUseCubic: false, fCubic: sk_cubic_resampler_t(fB: 0, fC: 0),
                                                 fFilter: LINEAR_SK_FILTER_MODE, fMipmap: LINEAR_SK_MIPMAP_MODE)
            return sk_image_scale_pixels(image, dst, &sampling, ALLOW_SK_IMAGE_CACHING_HINT)
        }
        guard ok else { throw RenderError("Could not read back pixels") }
        if !(outW == w && outH == h) { unpremultiply(&pixels) }
        return FrameImage(width: outW, height: outH, pixels: pixels)
    }

    private static func unpremultiply(_ pixels: inout [UInt8]) {
        pixels.withUnsafeMutableBufferPointer { p in
            var i = 0
            let n = p.count
            while i < n {
                let a = Int(p[i + 3])
                if a != 255 && a != 0 {
                    p[i] = UInt8(min(255, (Int(p[i]) * 255 + a / 2) / a))
                    p[i + 1] = UInt8(min(255, (Int(p[i + 1]) * 255 + a / 2) / a))
                    p[i + 2] = UInt8(min(255, (Int(p[i + 2]) * 255 + a / 2) / a))
                }
                i += 4
            }
        }
    }

    /// PNG bytes of a rectangle of a frame (always 8-bit RGBA, so every frame of an APNG has one format).
    static func encodePNG(_ frame: FrameImage, rect: (x: Int, y: Int, width: Int, height: Int)? = nil, level: Int32 = 6) throws -> [UInt8] {
        let r = rect ?? (0, 0, frame.width, frame.height)
        var imageInfo = info(r.width, r.height)
        guard let stream = sk_dynamicmemorywstream_new() else { throw RenderError("Could not allocate a stream") }
        defer { sk_dynamicmemorywstream_destroy(stream) }
        let ok: Bool = frame.pixels.withUnsafeBytes { buffer in
            let base = buffer.baseAddress!.advanced(by: (r.y * frame.width + r.x) * 4)
            guard let pixmap = sk_pixmap_new_with_params(&imageInfo, base, frame.width * 4) else { return false }
            defer { sk_pixmap_destructor(pixmap) }
            var options = sk_pngencoder_options_t(fFilterFlags: ALL_SK_PNGENCODER_FILTER_FLAGS, fZLibLevel: level, fComments: nil, fGainmap: nil, fGainmapInfo: nil)
            return sk_pngencoder_encode(stream, pixmap, &options)
        }
        guard ok else { throw RenderError("PNG encoding failed") }
        let size = sk_wstream_bytes_written(stream)
        var bytes = [UInt8](repeating: 0, count: size)
        bytes.withUnsafeMutableBytes { sk_dynamicmemorywstream_copy_to(stream, $0.baseAddress) }
        return bytes
    }

    static func write(_ bytes: [UInt8], to path: String) throws {
        guard FileManager.default.createFile(atPath: path, contents: Data(bytes)) else {
            throw RenderError("Could not write \(path)")
        }
    }

    /// A Skia image of the frame (the caller unrefs it).
    static func makeImage(_ frame: FrameImage) -> OpaquePointer? {
        var imageInfo = info(frame.width, frame.height)
        return frame.pixels.withUnsafeBytes { sk_image_new_raster_copy(&imageInfo, $0.baseAddress, frame.width * 4) }
    }
}
