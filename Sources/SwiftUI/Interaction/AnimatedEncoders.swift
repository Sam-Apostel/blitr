internal import CSkia

// Animated outputs of a capture (`--animated <file>`): the format follows the extension.
//
//  .png / .apng   APNG, lossless. Each frame is PNG-encoded by Skia; this file writes the acTL, fcTL and
//                 fdAT chunks around the image data. Frames store the bounding box of what changed.
//  .gif           GIFEncoder.swift.
//  .webp          Skia's animated WebP encoder (lossless).
//  .mp4 / .mov    frames piped to `ffmpeg` when it is on PATH.

struct TimedFrame {
    var image: FrameImage
    var milliseconds: Int
}

@MainActor
enum AnimatedOutput {
    static let extensions = ["png", "apng", "gif", "webp", "mp4", "mov"]

    static func write(_ frames: [TimedFrame], to path: String, fps: Int, gif: GIFOptions) throws {
        guard let first = frames.first else { throw RenderError("--animated: the capture has no frames") }
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "apng":
            try FramePixels.write(try APNGEncoder.encode(frames), to: path)
        case "gif":
            var encoder = GIFEncoder(width: first.image.width, height: first.image.height, options: gif)
            // GIF delays are hundredths of a second: carry the rounding error so the total stays right.
            var elapsed = 0, written = 0
            for frame in frames {
                elapsed += frame.milliseconds
                let cs = max(1, (elapsed + 5) / 10 - written)
                written += cs
                encoder.add(frame.image, centiseconds: cs)
            }
            try FramePixels.write(encoder.encode(), to: path)
        case "webp":
            try writeWebP(frames, to: path)
        case "mp4", "mov":
            try writeWithFFmpeg(frames, to: path, fps: fps)
        default:
            throw RenderError("--animated \(path): unknown format \".\(ext)\". Use .png (APNG), .gif, .webp, .mp4 or .mov")
        }
    }

    private static func writeWebP(_ frames: [TimedFrame], to path: String) throws {
        var pixmaps: [OpaquePointer?] = []
        defer { for p in pixmaps { sk_pixmap_destructor(p) } }
        // The pixel buffers must outlive the encode call.
        let buffers = frames.map { UnsafeMutablePointer<UInt8>.allocate(capacity: $0.image.pixels.count) }
        defer { for b in buffers { b.deallocate() } }
        var list: [sk_webpencoder_frame_t] = []
        for (i, frame) in frames.enumerated() {
            frame.image.pixels.withUnsafeBufferPointer { buffers[i].update(from: $0.baseAddress!, count: $0.count) }
            var info = sk_imageinfo_t(colorspace: sk_colorspace_new_srgb(), width: Int32(frame.image.width), height: Int32(frame.image.height),
                                      colorType: RGBA_8888_SK_COLORTYPE, alphaType: UNPREMUL_SK_ALPHATYPE)
            let pixmap = sk_pixmap_new_with_params(&info, buffers[i], frame.image.width * 4)
            pixmaps.append(pixmap)
            list.append(sk_webpencoder_frame_t(pixmap: pixmap, duration: Int32(frame.milliseconds)))
        }
        guard let stream = sk_filewstream_new(path), sk_filewstream_is_valid(stream) else { throw RenderError("Could not open \(path) for writing") }
        var options = sk_webpencoder_options_t(fCompression: LOSSLESS_SK_WEBPENCODER_COMPTRESSION, fQuality: 75)
        let ok = sk_webpencoder_encode_animated(stream, &list, Int32(list.count), &options)
        sk_filewstream_destroy(stream)
        guard ok else { throw RenderError("--animated \(path): WebP encoding failed") }
    }

    static func findExecutable(_ name: String) -> String? {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return paths.map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func writeWithFFmpeg(_ frames: [TimedFrame], to path: String, fps: Int) throws {
        guard let ffmpeg = findExecutable("ffmpeg") else {
            throw RenderError("--animated \(path): .mp4 and .mov need ffmpeg, which is not on PATH. Install ffmpeg, or use .gif, .png (APNG) or .webp, which are written without it.")
        }
        let first = frames[0].image
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        // Constant frame rate: a held frame is repeated. `bitexact` keeps the container free of dates and versions.
        process.arguments = ["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "\(first.width)x\(first.height)",
                             "-r", "\(fps)", "-i", "-", "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2:color=white", "-pix_fmt", "yuv420p",
                             "-threads", "1", "-fflags", "+bitexact", "-flags:v", "+bitexact", "-map_metadata", "-1", "-movflags", "+faststart", path]
        let input = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        do { try process.run() } catch { throw RenderError("--animated \(path): could not start ffmpeg: \(error.localizedDescription)") }
        let frameMs = 1000.0 / Double(max(1, fps))
        var owed = 0.0
        for frame in frames {
            owed += Double(frame.milliseconds) / frameMs
            let repeats = max(1, Int(owed.rounded()))
            owed -= Double(repeats)
            let data = Data(frame.image.pixels)
            for _ in 0..<repeats { input.fileHandleForWriting.write(data) }
        }
        try? input.fileHandleForWriting.close()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RenderError("--animated \(path): ffmpeg failed: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}

// MARK: - APNG

@MainActor
enum APNGEncoder {
    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        bytes.withUnsafeBufferPointer { p in
            crcTable.withUnsafeBufferPointer { t in
                for b in p { c = t[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
            }
        }
        return c ^ 0xFFFFFFFF
    }

    private static func be32(_ v: Int) -> [UInt8] { [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
    private static func be16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }

    private static func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
        let body = Array(type.utf8) + data
        return be32(data.count) + body + be32(Int(crc32(body)))
    }

    struct PNGChunk { var type: String; var data: [UInt8] }

    static func chunks(of png: [UInt8]) throws -> [PNGChunk] {
        guard png.count > 8, Array(png[0..<8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] else { throw RenderError("APNG: not a PNG") }
        var result: [PNGChunk] = []
        var i = 8
        while i + 12 <= png.count {
            let length = Int(png[i]) << 24 | Int(png[i + 1]) << 16 | Int(png[i + 2]) << 8 | Int(png[i + 3])
            let type = String(decoding: png[i + 4..<i + 8], as: UTF8.self)
            guard i + 12 + length <= png.count else { throw RenderError("APNG: truncated PNG chunk") }
            result.append(PNGChunk(type: type, data: Array(png[i + 8..<i + 8 + length])))
            i += 12 + length
        }
        return result
    }

    static func encode(_ frames: [TimedFrame]) throws -> [UInt8] {
        let first = frames[0].image
        let width = first.width, height = first.height
        // Opaque captures store unchanged pixels inside a frame's rectangle as clear and blend "over".
        let opaque = frames.allSatisfy { frame in
            frame.image.pixels.withUnsafeBufferPointer { p in
                var i = 3
                while i < p.count { if p[i] != 255 { return false }; i += 4 }
                return true
            }
        }
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        var sequence = 0
        var header: [UInt8]?
        var previous: FrameImage?
        for (index, frame) in frames.enumerated() {
            let image = frame.image
            guard image.width == width, image.height == height else { throw RenderError("APNG: frames differ in size") }
            var rect = (x: 0, y: 0, width: width, height: height)
            var source = image
            if let prev = previous {
                var minX = width, minY = height, maxX = -1, maxY = -1
                var masked = opaque ? image.pixels : []
                image.pixels.withUnsafeBufferPointer { cur in
                    prev.pixels.withUnsafeBufferPointer { old in
                        masked.withUnsafeMutableBufferPointer { m in
                            var i = 0
                            for y in 0..<height {
                                for x in 0..<width {
                                    if cur[i] == old[i] && cur[i + 1] == old[i + 1] && cur[i + 2] == old[i + 2] && cur[i + 3] == old[i + 3] {
                                        if opaque { m[i] = 0; m[i + 1] = 0; m[i + 2] = 0; m[i + 3] = 0 }
                                    } else {
                                        if x < minX { minX = x }
                                        if x > maxX { maxX = x }
                                        if y < minY { minY = y }
                                        if y > maxY { maxY = y }
                                    }
                                    i += 4
                                }
                            }
                        }
                    }
                }
                if maxX < 0 { minX = 0; minY = 0; maxX = 0; maxY = 0 }
                rect = (minX, minY, maxX - minX + 1, maxY - minY + 1)
                if opaque { source = FrameImage(width: width, height: height, pixels: masked) }
            }
            let png = try chunks(of: FramePixels.encodePNG(source, rect: rect, level: 9))
            guard let ihdr = png.first(where: { $0.type == "IHDR" }), ihdr.data.count == 13 else { throw RenderError("APNG: frame without IHDR") }
            if index == 0 {
                header = Array(ihdr.data[8...])
                out += chunk("IHDR", ihdr.data)
                // Color information of the first frame applies to all of them.
                for c in png where ["sRGB", "gAMA", "cHRM", "iCCP", "sBIT"].contains(c.type) { out += chunk(c.type, c.data) }
                out += chunk("acTL", be32(frames.count) + be32(0))
            } else if Array(ihdr.data[8...]) != header {
                throw RenderError("APNG: the PNG encoder changed pixel format between frames")
            }
            var control = be32(sequence) + be32(rect.width) + be32(rect.height) + be32(rect.x) + be32(rect.y)
            control += be16(max(1, frame.milliseconds)) + be16(1000)
            // dispose: none; blend: source (0) or over (1).
            control += [0, index > 0 && opaque ? 1 : 0]
            out += chunk("fcTL", control)
            sequence += 1
            for c in png where c.type == "IDAT" {
                if index == 0 {
                    out += chunk("IDAT", c.data)
                } else {
                    out += chunk("fdAT", be32(sequence) + c.data)
                    sequence += 1
                }
            }
            previous = image
        }
        out += chunk("IEND", [])
        return out
    }
}
