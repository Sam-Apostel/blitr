// A GIF89a encoder for captured frames.
//
//  - One global palette for the whole animation (median cut over a 15-bit histogram of every frame), or
//    a palette per frame (`--gif-palette local`): better colors for captures that change scene, larger files.
//  - Optional ordered (Bayer 4x4) dithering: stable between frames, so it does not defeat frame differencing.
//  - Frame differencing: each frame stores only the bounding box of what changed, with unchanged pixels
//    inside it written as the transparent index (disposal "do not dispose"), then LZW.
//  - Fully transparent pixels of the source (alpha < 128) stay transparent.
//
// Everything is integer arithmetic over the frames in order: same frames, same bytes.

struct GIFOptions {
    var localPalettes = false
    var dither = false
    /// 0 loops forever.
    var loopCount = 0
}

struct GIFEncoder {
    let width: Int
    let height: Int
    var options = GIFOptions()
    private var frames: [(image: FrameImage, centiseconds: Int)] = []

    init(width: Int, height: Int, options: GIFOptions = GIFOptions()) {
        self.width = width
        self.height = height
        self.options = options
    }

    mutating func add(_ image: FrameImage, centiseconds: Int) {
        frames.append((image, max(1, centiseconds)))
    }

    // MARK: Palette (median cut)

    struct Palette {
        /// Up to 255 colors (index 255 is reserved for transparency), r,g,b each.
        var colors: [UInt8] = []
        var count: Int { colors.count / 3 }
        /// Nearest color for each 15-bit rgb, filled on demand (-1: not computed).
        var cache = [Int16](repeating: -1, count: 32768)

        mutating func index(r: Int, g: Int, b: Int) -> Int {
            let key = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
            let cached = cache[key]
            if cached >= 0 { return Int(cached) }
            // The bin's centre stands for every color in it.
            let cr = (r & ~7) + 4, cg = (g & ~7) + 4, cb = (b & ~7) + 4
            var best = 0, bestDistance = Int.max
            colors.withUnsafeBufferPointer { c in
                var i = 0, n = 0
                while i < c.count {
                    let dr = cr - Int(c[i]), dg = cg - Int(c[i + 1]), db = cb - Int(c[i + 2])
                    // Weighted for perception (green counts most).
                    let d = 2 * dr * dr + 4 * dg * dg + 3 * db * db
                    if d < bestDistance { bestDistance = d; best = n }
                    i += 3
                    n += 1
                }
            }
            cache[key] = Int16(best)
            return best
        }
    }

    private struct Box {
        var bins: [Int]
        var count: Int
        var rMin = 31, rMax = 0, gMin = 31, gMax = 0, bMin = 31, bMax = 0
        var longest: (range: Int, channel: Int) {
            // Same weights as the nearest-color search.
            let r = (rMax - rMin) * 2, g = (gMax - gMin) * 4, b = (bMax - bMin) * 3
            if g >= r && g >= b { return (g, 1) }
            return r >= b ? (r, 0) : (b, 2)
        }
    }

    static func buildPalette(_ images: [FrameImage], maxColors: Int = 255) -> Palette {
        var histogram = [Int](repeating: 0, count: 32768)
        var sumR = [Int](repeating: 0, count: 32768), sumG = [Int](repeating: 0, count: 32768), sumB = [Int](repeating: 0, count: 32768)
        for image in images {
            image.pixels.withUnsafeBufferPointer { p in
                var i = 0
                let n = p.count
                while i < n {
                    if p[i + 3] >= 128 {
                        let r = Int(p[i]), g = Int(p[i + 1]), b = Int(p[i + 2])
                        let key = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
                        histogram[key] += 1
                        sumR[key] += r; sumG[key] += g; sumB[key] += b
                    }
                    i += 4
                }
            }
        }
        func makeBox(_ bins: [Int]) -> Box {
            var box = Box(bins: bins, count: 0)
            for k in bins {
                let r = k >> 10, g = (k >> 5) & 31, b = k & 31
                box.count += histogram[k]
                box.rMin = min(box.rMin, r); box.rMax = max(box.rMax, r)
                box.gMin = min(box.gMin, g); box.gMax = max(box.gMax, g)
                box.bMin = min(box.bMin, b); box.bMax = max(box.bMax, b)
            }
            return box
        }
        let used = (0..<32768).filter { histogram[$0] > 0 }
        var palette = Palette()
        guard !used.isEmpty else {
            palette.colors = [0, 0, 0]
            return palette
        }
        var boxes = [makeBox(used)]
        while boxes.count < maxColors {
            // Split the box with the most pixels among those that can still be split.
            var pick = -1, best = -1
            for (i, box) in boxes.enumerated() where box.bins.count > 1 {
                let score = box.count * (box.longest.range + 1)
                if score > best { best = score; pick = i }
            }
            guard pick >= 0 else { break }
            let box = boxes[pick]
            let channel = box.longest.channel
            func component(_ k: Int) -> Int { channel == 0 ? k >> 10 : channel == 1 ? (k >> 5) & 31 : k & 31 }
            let sorted = box.bins.sorted { (component($0), $0) < (component($1), $1) }
            var running = 0, cut = 1
            for (i, k) in sorted.enumerated() {
                running += histogram[k]
                if running * 2 >= box.count { cut = max(1, min(sorted.count - 1, i + 1)); break }
            }
            boxes[pick] = makeBox(Array(sorted[..<cut]))
            boxes.append(makeBox(Array(sorted[cut...])))
        }
        for box in boxes {
            var r = 0, g = 0, b = 0
            for k in box.bins { r += sumR[k]; g += sumG[k]; b += sumB[k] }
            let n = max(1, box.count)
            palette.colors += [UInt8((r + n / 2) / n), UInt8((g + n / 2) / n), UInt8((b + n / 2) / n)]
        }
        return palette
    }

    private static let bayer: [Int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

    /// Palette indices of an image (255 for transparent pixels).
    static func quantize(_ image: FrameImage, _ palette: inout Palette, dither: Bool) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: image.width * image.height)
        let w = image.width
        image.pixels.withUnsafeBufferPointer { p in
            out.withUnsafeMutableBufferPointer { o in
                var i = 0, n = 0
                let total = o.count
                while n < total {
                    if p[i + 3] < 128 {
                        o[n] = 255
                    } else {
                        var r = Int(p[i]), g = Int(p[i + 1]), b = Int(p[i + 2])
                        if dither {
                            // +-4 levels: half a 15-bit bin either way.
                            let t = bayer[((n / w) & 3) * 4 + ((n % w) & 3)] - 8
                            let d = t / 2
                            r = min(255, max(0, r + d)); g = min(255, max(0, g + d)); b = min(255, max(0, b + d))
                        }
                        o[n] = UInt8(palette.index(r: r, g: g, b: b))
                    }
                    i += 4
                    n += 1
                }
            }
        }
        return out
    }

    // MARK: Encoding

    func encode() -> [UInt8] {
        var out: [UInt8] = []
        func word(_ v: Int) { out.append(UInt8(v & 0xFF)); out.append(UInt8((v >> 8) & 0xFF)) }
        func colorTable(_ palette: Palette) {
            out += palette.colors
            out += [UInt8](repeating: 0, count: (256 - palette.count) * 3)
        }
        out += Array("GIF89a".utf8)
        word(width); word(height)
        var global = options.localPalettes ? Palette() : GIFEncoder.buildPalette(frames.map(\.image))
        if options.localPalettes {
            out += [0x70, 0, 0]  // no global color table
        } else {
            out += [0xF7, 0, 0]  // global table, 256 entries, 8 bits
            colorTable(global)
        }
        if frames.count > 1 {
            out += [0x21, 0xFF, 0x0B] + Array("NETSCAPE2.0".utf8) + [0x03, 0x01]
            word(options.loopCount)
            out.append(0)
        }
        // With transparent pixels anywhere, "keep what was there" cannot express a pixel turning
        // transparent: every frame is then stored whole and the canvas cleared between frames.
        let transparent = frames.contains { frame in
            frame.image.pixels.withUnsafeBufferPointer { p in
                var i = 3
                while i < p.count { if p[i] < 128 { return true }; i += 4 }
                return false
            }
        }
        var previous: [UInt8]?
        var previousImage: FrameImage?
        for (image, centiseconds) in frames {
            var palette = global
            if options.localPalettes { palette = GIFEncoder.buildPalette([image]) }
            var indexed = GIFEncoder.quantize(image, &palette, dither: options.dither)
            if !options.localPalettes { global = palette }
            let full = indexed
            var x0 = 0, y0 = 0, x1 = width - 1, y1 = height - 1
            if !transparent, let prev = previous, let prevImage = previousImage {
                var minX = width, minY = height, maxX = -1, maxY = -1
                let w = width, h = height, local = options.localPalettes
                indexed.withUnsafeMutableBufferPointer { cur in
                    prev.withUnsafeBufferPointer { old in
                        image.pixels.withUnsafeBufferPointer { rgb in
                            prevImage.pixels.withUnsafeBufferPointer { oldRGB in
                                var n = 0
                                for y in 0..<h {
                                    for x in 0..<w {
                                        let same: Bool
                                        if local {
                                            let i = n * 4
                                            same = rgb[i] == oldRGB[i] && rgb[i + 1] == oldRGB[i + 1] && rgb[i + 2] == oldRGB[i + 2]
                                        } else {
                                            same = cur[n] == old[n]
                                        }
                                        if same {
                                            cur[n] = 255
                                        } else {
                                            if x < minX { minX = x }
                                            if x > maxX { maxX = x }
                                            if y < minY { minY = y }
                                            if y > maxY { maxY = y }
                                        }
                                        n += 1
                                    }
                                }
                            }
                        }
                    }
                }
                if maxX < 0 { minX = 0; minY = 0; maxX = 0; maxY = 0 }
                x0 = minX; y0 = minY; x1 = maxX; y1 = maxY
            }
            previous = full
            previousImage = image
            let w = x1 - x0 + 1, h = y1 - y0 + 1
            // Graphic control: transparent index 255; disposal 1 (leave in place) or 2 (clear) with transparency.
            out += [0x21, 0xF9, 0x04, transparent ? 0x09 : 0x05]
            word(centiseconds)
            out += [255, 0]
            out.append(0x2C)
            word(x0); word(y0); word(w); word(h)
            if options.localPalettes {
                out.append(0x87)
                colorTable(palette)
            } else {
                out.append(0)
            }
            var region = [UInt8](repeating: 0, count: w * h)
            let fullWidth = width
            region.withUnsafeMutableBufferPointer { r in
                indexed.withUnsafeBufferPointer { ix in
                    for y in 0..<h {
                        let row = (y0 + y) * fullWidth + x0
                        for x in 0..<w { r[y * w + x] = ix[row + x] }
                    }
                }
            }
            out.append(8)
            let data = GIFEncoder.lzw(region)
            var offset = 0
            while offset < data.count {
                let n = min(255, data.count - offset)
                out.append(UInt8(n))
                out += data[offset..<offset + n]
                offset += n
            }
            out.append(0)
        }
        out.append(0x3B)
        return out
    }

    /// Variable-width LZW with 8-bit symbols, as GIF wants it.
    static func lzw(_ input: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(input.count / 2)
        var bitBuffer: UInt32 = 0, bitCount = 0
        func emit(_ code: Int, _ size: Int, _ out: inout [UInt8], _ buffer: inout UInt32, _ count: inout Int) {
            buffer |= UInt32(code) << UInt32(count)
            count += size
            while count >= 8 {
                out.append(UInt8(buffer & 0xFF))
                buffer >>= 8
                count -= 8
            }
        }
        let clear = 256, end = 257
        // Open-addressed table of (prefix << 8 | byte) -> code.
        let tableSize = 8192
        var keys = [Int32](repeating: -1, count: tableSize)
        var values = [Int16](repeating: 0, count: tableSize)
        var next = 258, size = 9
        emit(clear, size, &out, &bitBuffer, &bitCount)
        guard !input.isEmpty else {
            emit(end, size, &out, &bitBuffer, &bitCount)
            if bitCount > 0 { out.append(UInt8(bitBuffer & 0xFF)) }
            return out
        }
        input.withUnsafeBufferPointer { p in
            keys.withUnsafeMutableBufferPointer { k in
                values.withUnsafeMutableBufferPointer { v in
                    var prefix = Int(p[0])
                    var i = 1
                    let n = p.count
                    while i < n {
                        let byte = Int(p[i])
                        let key = Int32(prefix << 8 | byte)
                        var slot = (prefix * 31 + byte * 7919) & (tableSize - 1)
                        var found = -1
                        while k[slot] != -1 {
                            if k[slot] == key { found = Int(v[slot]); break }
                            slot = (slot + 1) & (tableSize - 1)
                        }
                        if found >= 0 {
                            prefix = found
                        } else {
                            emit(prefix, size, &out, &bitBuffer, &bitCount)
                            if next < 4096 {
                                k[slot] = key
                                v[slot] = Int16(next)
                                if next == 1 << size { size += 1 }
                                next += 1
                            } else {
                                emit(clear, size, &out, &bitBuffer, &bitCount)
                                for j in 0..<tableSize { k[j] = -1 }
                                next = 258
                                size = 9
                            }
                            prefix = byte
                        }
                        i += 1
                    }
                    emit(prefix, size, &out, &bitBuffer, &bitCount)
                }
            }
        }
        emit(end, size, &out, &bitBuffer, &bitCount)
        if bitCount > 0 { out.append(UInt8(bitBuffer & 0xFF)) }
        return out
    }
}
