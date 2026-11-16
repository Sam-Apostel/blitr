internal import CSkia
internal import CHarfBuzz

// Paragraph layout: shape runs with HarfBuzz, break lines, truncate, and draw glyphs with Skia.
// Left-to-right only for now.

struct TextRun {
    var text: String
    var font: ResolvedFont
    var paint: _Paint
    var underline: RGBA? = nil
    var strikethrough: RGBA? = nil
    var background: RGBA? = nil
    var kerning: CGFloat = 0
    var baselineOffset: CGFloat = 0
    /// Inline attachment (an image in text): occupies `size` on the baseline and draws itself.
    var attachment: InlineAttachment? = nil
}

struct InlineAttachment {
    var size: CGSize
    /// Distance the attachment's bottom sits below the baseline.
    var descent: CGFloat
    var draw: @MainActor (Painter, CGRect) -> Void
}

struct TextLayoutOptions {
    var lineLimit: Int? = nil
    var alignment: TextAlignment = .leading
    var truncation: Text.TruncationMode = .tail
    var lineSpacing: CGFloat = 0
    var minimumScaleFactor: CGFloat = 1
    var scale: CGFloat = 3
    /// Moves a word down so a wrapped paragraph never ends on a single word, as iOS's standard
    /// line-break strategy does (measured: iOS 27.0 simulator, "...track your habits and stay /
    /// focused." wraps as "...track your habits and / stay focused.").
    var avoidsOrphans = false
}

@MainActor
final class TextLayout {
    struct Glyph {
        var id: UInt16
        var advance: CGFloat
        var xOffset: CGFloat
        var yOffset: CGFloat
        var cluster: Int
        var run: Int
        var instance: FontInstance?
        var size: CGFloat
        /// A line may end after this glyph.
        var breakAfter = false
        var isWhitespace = false
        var isNewline = false
    }
    struct Line {
        var glyphs: [Glyph]
        var width: CGFloat
        var ascent: CGFloat
        var descent: CGFloat
        var x: CGFloat = 0
        var baseline: CGFloat = 0
        /// Space added above this line when it follows another (a text style's line advance
        /// beyond the font's height).
        var leading: CGFloat = 0
        /// Width of the whitespace the line wrapped at, counted in the text's width on iOS.
        var trailingSpace: CGFloat = 0
    }

    let runs: [TextRun]
    let options: TextLayoutOptions
    private(set) var lines: [Line] = []
    private(set) var size: CGSize = .zero
    private(set) var firstBaseline: CGFloat = 0
    private(set) var lastBaseline: CGFloat = 0
    private(set) var isTruncated = false

    private static var shapeCache: [ShapeKey: [Glyph]] = [:]
    private struct ShapeKey: Hashable { var text: String; var font: ResolvedFont; var kerning: CGFloat }

    init(runs: [TextRun], width: CGFloat?, height: CGFloat? = nil, options: TextLayoutOptions) {
        self.runs = runs
        self.options = options
        var factor: CGFloat = 1
        layout(width: width, fontScale: factor)
        // minimumScaleFactor: shrink in steps until the text fits untruncated, and within the
        // height offered (SwiftUI shrinks text that a full stack squeezes vertically).
        func overflows() -> Bool { isTruncated || height.map { size.height > $0 + 0.01 } ?? false }
        while overflows(), options.minimumScaleFactor < 1, factor > options.minimumScaleFactor {
            factor = max(options.minimumScaleFactor, factor - 0.05)
            layout(width: width, fontScale: factor)
        }
    }

    // MARK: Shaping

    private func shape(_ runIndex: Int, fontScale: CGFloat) -> [Glyph] {
        let run = runs[runIndex]
        var font = run.font
        font.size = font.size * fontScale
        if let attachment = run.attachment {
            var g = Glyph(id: 0, advance: attachment.size.width * fontScale, xOffset: 0, yOffset: 0, cluster: 0, run: runIndex, instance: nil, size: font.size)
            g.breakAfter = true
            return [g]
        }
        let key = ShapeKey(text: run.text, font: font, kerning: run.kerning)
        if let cached = TextLayout.shapeCache[key] {
            return cached.map { var g = $0; g.run = runIndex; return g }
        }
        let primary = FontLibrary.shared.instance(for: font)
        let utf8 = Array(run.text.utf8)
        var result: [Glyph] = []

        // Split into segments by which font covers each character (primary, or a fallback for emoji etc.).
        var segments: [(start: Int, end: Int, instance: FontInstance)] = []
        var offset = 0
        var previousWasJoiner = false
        for scalar in run.text.unicodeScalars {
            let length = String(scalar).utf8.count
            defer { offset += length }
            let sticky = scalar.value == 0x200D || scalar.value == 0xFE0F || (0x1F3FB...0x1F3FF).contains(scalar.value)
                || scalar.properties.generalCategory == .nonspacingMark || previousWasJoiner
            previousWasJoiner = scalar.value == 0x200D
            var instance = primary
            if sticky, let last = segments.last {
                instance = last.instance
            } else if scalar.properties.isEmojiPresentation || !primary.hasGlyph(scalar) {
                if scalar.value >= 0x20, let fallback = FontLibrary.shared.fallbackInstance(for: scalar, like: font) { instance = fallback }
            }
            if let last = segments.last, last.instance === instance {
                segments[segments.count - 1].end = offset + length
            } else {
                segments.append((offset, offset + length, instance))
            }
        }

        for segment in segments {
            let buffer = hb_buffer_create()
            defer { hb_buffer_destroy(buffer) }
            utf8.withUnsafeBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: utf8.count) {
                    hb_buffer_add_utf8(buffer, $0, Int32(utf8.count), UInt32(segment.start), Int32(segment.end - segment.start))
                }
            }
            hb_buffer_set_direction(buffer, HB_DIRECTION_LTR)
            hb_buffer_guess_segment_properties(buffer)
            hb_buffer_set_direction(buffer, HB_DIRECTION_LTR)
            var features: [hb_feature_t] = []
            func feature(_ tag: String) { features.append(hb_feature_t(tag: fourCC(tag), value: 1, start: 0, end: UInt32.max)) }
            if font.monospacedDigit { feature("tnum") }
            if font.smallCaps { feature("smcp") }
            // A sub-font carrying the point size: HarfBuzz only applies size-dependent tracking
            // (Apple's `trak` table) when it knows the size.
            let sized = hb_font_create_sub_font(segment.instance.hbFont)
            hb_font_set_ptem(sized, Float(font.size))
            hb_shape(sized, buffer, features, UInt32(features.count))
            hb_font_destroy(sized)
            var count: UInt32 = 0
            let infos = hb_buffer_get_glyph_infos(buffer, &count)!
            let positions = hb_buffer_get_glyph_positions(buffer, &count)!
            let unit = font.size / segment.instance.file.unitsPerEm * segment.instance.advanceScale
            let substitute = segment.instance.sfProMetrics
            let plainUnit = font.size / segment.instance.file.unitsPerEm
            for i in 0..<Int(count) {
                var advance = CGFloat(positions[i].x_advance) * unit
                if let substitute {
                    // One character drawn by one glyph: give it SF Pro's width, keeping whatever
                    // pair kerning the substitute applied on top of its own nominal advance.
                    let cluster = Int(infos[i].cluster)
                    let alone = (i == 0 || infos[i - 1].cluster != infos[i].cluster)
                        && (i + 1 == Int(count) || infos[i + 1].cluster != infos[i].cluster)
                    let nextCluster = i + 1 < Int(count) ? Int(infos[i + 1].cluster) : segment.end
                    if alone, let scalar = TextLayout.scalar(in: utf8, at: cluster, length: nextCluster - cluster),
                       let width = substitute.advance(of: scalar, tabularDigits: font.monospacedDigit) {
                        let nominal = CGFloat(hb_font_get_glyph_h_advance(segment.instance.hbFont, infos[i].codepoint))
                        advance = width + (CGFloat(positions[i].x_advance) - nominal) * plainUnit
                    }
                }
                var g = Glyph(id: UInt16(truncatingIfNeeded: infos[i].codepoint),
                              advance: advance + run.kerning,
                              xOffset: CGFloat(positions[i].x_offset) * unit,
                              yOffset: CGFloat(positions[i].y_offset) * unit,
                              cluster: Int(infos[i].cluster), run: runIndex, instance: segment.instance, size: font.size)
                let byte = utf8[g.cluster]
                if byte == 0x0A { g.isNewline = true; g.advance = 0 }
                if byte == 0x20 || byte == 0x09 { g.isWhitespace = true; g.breakAfter = true }
                if byte == 0x2D { g.breakAfter = true }
                if segment.instance.isColor { g.breakAfter = true }
                result.append(g)
            }
        }
        // East Asian text can break between any two characters.
        for scalar in run.text.unicodeScalars where (0x2E80...0x9FFF).contains(scalar.value) || (0xAC00...0xD7AF).contains(scalar.value) {
            _ = scalar
            for i in result.indices where utf8[result[i].cluster] >= 0xE2 { result[i].breakAfter = true }
            break
        }
        if TextLayout.shapeCache.count > 4000 { TextLayout.shapeCache.removeAll() }
        TextLayout.shapeCache[key] = result
        return result
    }

    /// The single scalar encoded by exactly `length` UTF-8 bytes at `offset`, if that is what is there.
    private static func scalar(in utf8: [UInt8], at offset: Int, length: Int) -> Unicode.Scalar? {
        guard length >= 1, length <= 4, offset >= 0, offset + length <= utf8.count else { return nil }
        var iterator = utf8[offset..<(offset + length)].makeIterator()
        var decoder = UTF8()
        guard case .scalarValue(let scalar) = decoder.decode(&iterator), iterator.next() == nil else { return nil }
        return scalar
    }

    private func metrics(_ g: Glyph) -> (ascent: CGFloat, descent: CGFloat) {
        let run = runs[g.run]
        if let a = run.attachment {
            let s = g.size / max(run.font.size, 0.001)
            return ((a.size.height - a.descent) * s + run.baselineOffset, a.descent * s - run.baselineOffset)
        }
        // Line height follows the run's own font, so a fallback glyph (emoji) never changes it.
        let instance = FontLibrary.shared.instance(for: run.font)
        let m = run.font.lineHeightMultiple
        return (instance.ascent * g.size * m + max(0, run.baselineOffset), instance.descent * g.size * m + max(0, -run.baselineOffset))
    }

    /// Extra space between wrapped lines that a run's font asks for.
    func leading(of run: TextRun, size: CGFloat) -> CGFloat {
        guard let advance = run.font.lineAdvance, run.attachment == nil else { return 0 }
        let instance = FontLibrary.shared.instance(for: run.font)
        let scale = size / max(run.font.size, 0.001)
        return max(0, advance * scale - (instance.ascent + instance.descent) * size * run.font.lineHeightMultiple)
    }

    // MARK: Line breaking

    private func layout(width: CGFloat?, fontScale: CGFloat) {
        lines = []
        isTruncated = false
        let maxWidth = (width.map { $0.isFinite ? $0 : nil } ?? nil).map { max(0, $0) + 0.01 }
        var glyphs: [Glyph] = []
        for i in runs.indices { glyphs.append(contentsOf: shape(i, fontScale: fontScale)) }

        var raw: [[Glyph]] = []
        var current: [Glyph] = []
        var currentWidth: CGFloat = 0
        var i = 0
        var paragraphEnds = Set<Int>()
        func flush() { raw.append(current); current = []; currentWidth = 0 }
        while i < glyphs.count {
            if glyphs[i].isNewline { flush(); paragraphEnds.insert(raw.count - 1); i += 1; continue }
            // A "word" runs up to and including the next break opportunity.
            var j = i
            var wordWidth: CGFloat = 0, trailingSpace: CGFloat = 0
            while j < glyphs.count, !glyphs[j].isNewline {
                wordWidth += glyphs[j].advance
                trailingSpace = glyphs[j].isWhitespace ? trailingSpace + glyphs[j].advance : 0
                j += 1
                if glyphs[j - 1].breakAfter { break }
            }
            if let maxWidth, currentWidth + wordWidth - trailingSpace > maxWidth {
                if !current.isEmpty { flush() }
                if wordWidth - trailingSpace > maxWidth {
                    // The word alone is too wide: break it between clusters.
                    var k = i
                    while k < j {
                        if currentWidth + glyphs[k].advance > maxWidth, !current.isEmpty,
                           k == 0 || glyphs[k].cluster != glyphs[k - 1].cluster || glyphs[k].run != glyphs[k - 1].run { flush() }
                        current.append(glyphs[k]); currentWidth += glyphs[k].advance; k += 1
                    }
                    i = j
                    continue
                }
            }
            current.append(contentsOf: glyphs[i..<j])
            currentWidth += wordWidth
            i = j
        }
        if !current.isEmpty || raw.isEmpty || (glyphs.last?.isNewline ?? false) { flush() }
        paragraphEnds.insert(raw.count - 1)
        if options.avoidsOrphans, let maxWidth, options.lineLimit.map({ raw.count <= $0 }) ?? true {
            for end in paragraphEnds.sorted() where end > 0 && !paragraphEnds.contains(end - 1) {
                raw[end - 1...end] = ArraySlice(TextLayout.pushOut(raw[end - 1], raw[end], maxWidth: maxWidth))
            }
        }

        // Line limit and truncation.
        let limit = options.lineLimit.map { max(1, $0) }
        if let limit, raw.count > limit {
            let overflow = raw[limit...].flatMap { $0 }
            raw = Array(raw[..<limit])
            raw[limit - 1].append(contentsOf: overflow)
            isTruncated = true
        }
        for (index, var lineGlyphs) in raw.enumerated() {
            var trailing: CGFloat = 0
            while let last = lineGlyphs.last, last.isWhitespace, lineGlyphs.count > 1 || index < raw.count - 1 {
                trailing += last.advance
                lineGlyphs.removeLast()
            }
            // iOS counts the space a line wrapped at in the text's width (the glyphs are still
            // aligned without it). measured: iOS 27.0 simulator, Hello and 08_Onboarding frames.
            if !options.avoidsOrphans || paragraphEnds.contains(index) { trailing = 0 }
            var lineWidth = lineGlyphs.reduce(0) { $0 + $1.advance }
            if let maxWidth, lineWidth > maxWidth, !lineGlyphs.isEmpty {
                isTruncated = true
                lineGlyphs = truncate(lineGlyphs, to: maxWidth, fontScale: fontScale)
                lineWidth = lineGlyphs.reduce(0) { $0 + $1.advance }
            } else if isTruncated, index == raw.count - 1, limit != nil, let maxWidth {
                lineGlyphs = truncate(lineGlyphs, to: maxWidth, fontScale: fontScale, force: true)
                lineWidth = lineGlyphs.reduce(0) { $0 + $1.advance }
            }
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            if lineGlyphs.isEmpty, let run = runs.last ?? nil {
                let inst = FontLibrary.shared.instance(for: run.font)
                ascent = inst.ascent * run.font.size * fontScale
                descent = inst.descent * run.font.size * fontScale
                leading = self.leading(of: run, size: run.font.size * fontScale)
            }
            for g in lineGlyphs {
                let m = metrics(g)
                ascent = max(ascent, m.ascent); descent = max(descent, m.descent)
                leading = max(leading, self.leading(of: runs[g.run], size: g.size))
            }
            lines.append(Line(glyphs: lineGlyphs, width: lineWidth, ascent: ascent, descent: descent, leading: leading,
                              trailingSpace: trailing))
        }

        // Geometry. Sizes are rounded up to whole pixels, as SwiftUI does for text.
        func ceilPx(_ v: CGFloat) -> CGFloat { (v * options.scale - 0.001).rounded(.up) / options.scale }
        var contentWidth = lines.map { $0.width + $0.trailingSpace }.max() ?? 0
        // That space never makes the text wider than it was offered. measured: watchOS 26.5 simulator (Watch
        // "Text styles" on the Ultra 2: a body line that fits 201pt only without its space is 201pt wide, not 203).
        if RenderedPlatform.platform == .watchOS, let maxWidth {
            contentWidth = min(contentWidth, max(maxWidth - 0.01, lines.map(\.width).max() ?? 0))
        }
        let boxWidth = ceilPx(contentWidth)
        var y: CGFloat = 0
        for index in lines.indices {
            if index > 0 { y += options.lineSpacing + lines[index].leading }
            lines[index].baseline = y + lines[index].ascent
            y += lines[index].ascent + lines[index].descent
            switch options.alignment {
            case .leading: lines[index].x = 0
            case .center: lines[index].x = (boxWidth - lines[index].width) / 2
            case .trailing: lines[index].x = boxWidth - lines[index].width
            }
        }
        size = CGSize(width: boxWidth, height: ceilPx(y))
        firstBaseline = lines.first?.baseline ?? 0
        lastBaseline = lines.last?.baseline ?? 0
    }

    /// Moves the last word of `previous` onto `last` when `last` holds a single word and the
    /// result still fits.
    private static func pushOut(_ previous: [Glyph], _ last: [Glyph], maxWidth: CGFloat) -> [[Glyph]] {
        func trimmed(_ g: [Glyph]) -> ArraySlice<Glyph> {
            var end = g.count
            while end > 0, g[end - 1].isWhitespace { end -= 1 }
            return g[..<end]
        }
        let lastWord = trimmed(last)
        guard !lastWord.isEmpty, !lastWord.dropLast().contains(where: \.breakAfter),
              !lastWord.contains(where: { $0.instance?.isColor ?? false }) else { return [previous, last] }
        let body = trimmed(previous)
        guard let cut = body.indices.dropLast().last(where: { body[$0].breakAfter }).map({ $0 + 1 }), cut > 0 else {
            return [previous, last]
        }
        let moved = Array(previous[cut...])
        let width = moved.reduce(0) { $0 + $1.advance } + lastWord.reduce(0) { $0 + $1.advance }
        guard width <= maxWidth else { return [previous, last] }
        return [Array(previous[..<cut]), moved + last]
    }

    private func truncate(_ glyphs: [Glyph], to maxWidth: CGFloat, fontScale: CGFloat, force: Bool = false) -> [Glyph] {
        guard let template = glyphs.last(where: { $0.instance != nil }) ?? glyphs.last else { return glyphs }
        var ellipsisRun = runs[template.run]
        ellipsisRun.text = "…"
        ellipsisRun.attachment = nil
        let helper = TextLayoutShaper(run: ellipsisRun, runIndex: template.run, fontScale: fontScale)
        let ellipsis = helper.glyphs
        let ellipsisWidth = ellipsis.reduce(0) { $0 + $1.advance }
        let total = glyphs.reduce(0) { $0 + $1.advance }
        if !force && total <= maxWidth { return glyphs }
        switch options.truncation {
        case .tail:
            var kept: [Glyph] = [], w: CGFloat = 0
            for g in glyphs {
                if w + g.advance + ellipsisWidth > maxWidth { break }
                kept.append(g); w += g.advance
            }
            while let last = kept.last, last.isWhitespace { kept.removeLast() }
            return kept + ellipsis
        case .head:
            var kept: [Glyph] = [], w: CGFloat = 0
            for g in glyphs.reversed() {
                if w + g.advance + ellipsisWidth > maxWidth { break }
                kept.insert(g, at: 0); w += g.advance
            }
            return ellipsis + kept
        case .middle:
            let half = (maxWidth - ellipsisWidth) / 2
            var head: [Glyph] = [], tail: [Glyph] = [], w: CGFloat = 0
            for g in glyphs { if w + g.advance > half { break }; head.append(g); w += g.advance }
            w = 0
            for g in glyphs.reversed() { if w + g.advance > half { break }; tail.insert(g, at: 0); w += g.advance }
            return head + ellipsis + tail
        }
    }

    /// Shapes a single run outside a layout (used for the ellipsis).
    private struct TextLayoutShaper {
        let glyphs: [Glyph]
        @MainActor init(run: TextRun, runIndex: Int, fontScale: CGFloat) {
            let layout = TextLayout(shaping: run, fontScale: fontScale)
            glyphs = layout.lines.first?.glyphs.map { var g = $0; g.run = runIndex; return g } ?? []
        }
    }

    private init(shaping run: TextRun, fontScale: CGFloat) {
        runs = [run]
        options = TextLayoutOptions()
        lines = [Line(glyphs: shape(0, fontScale: fontScale), width: 0, ascent: 0, descent: 0)]
    }

    // MARK: Drawing

    func draw(_ p: Painter, in bounds: CGRect) {
        // When the view is wider than the text, alignment applies within the view.
        let extra = bounds.width - size.width
        let dx: CGFloat = extra <= 0 ? 0 : options.alignment == .center ? extra / 2 : options.alignment == .trailing ? extra : 0
        for line in lines {
            var x = line.x + dx
            var index = 0
            let glyphs = line.glyphs
            while index < glyphs.count {
                // Batch consecutive glyphs sharing run, font and size into one blob.
                let first = glyphs[index]
                let run = runs[first.run]
                var end = index
                var batchWidth: CGFloat = 0
                while end < glyphs.count, glyphs[end].run == first.run, glyphs[end].instance === first.instance, glyphs[end].size == first.size {
                    batchWidth += glyphs[end].advance
                    end += 1
                }
                let baseline = line.baseline - run.baselineOffset
                if let color = run.background {
                    let metrics = FontLibrary.shared.instance(for: run.font)
                    let rect = CGRect(x: x, y: baseline - metrics.ascent * first.size, width: batchWidth,
                                      height: (metrics.ascent + metrics.descent) * first.size)
                    p.fill(Path(rect), with: .color(color), in: rect)
                }
                if let attachment = run.attachment {
                    let s = first.size / max(run.font.size, 0.001)
                    let rect = CGRect(x: x, y: baseline + attachment.descent * s - attachment.size.height * s,
                                      width: attachment.size.width * s, height: attachment.size.height * s)
                    attachment.draw(p, rect)
                } else if let instance = first.instance {
                    drawGlyphs(p, glyphs[index..<end], instance: instance, x: x, baseline: baseline, paint: run.paint, bounds: bounds)
                }
                let reference = FontLibrary.shared.instance(for: run.font)
                if let color = run.underline {
                    let t = max(1 / p.scale, reference.underlineThickness * first.size)
                    let rect = CGRect(x: x, y: baseline + reference.underlineOffset * first.size, width: batchWidth, height: t)
                    p.fill(Path(rect), with: .color(color), in: rect)
                }
                if let color = run.strikethrough {
                    let t = max(1 / p.scale, reference.underlineThickness * first.size)
                    let rect = CGRect(x: x, y: baseline - reference.xHeight * first.size / 2 - t / 2, width: batchWidth, height: t)
                    p.fill(Path(rect), with: .color(color), in: rect)
                }
                x += batchWidth
                index = end
            }
        }
    }

    private func drawGlyphs(_ p: Painter, _ glyphs: ArraySlice<Glyph>, instance: FontInstance, x: CGFloat, baseline: CGFloat,
                            paint: _Paint, bounds: CGRect) {
        guard let size = glyphs.first?.size, !glyphs.isEmpty else { return }
        let font = sk_font_new_with_values(instance.skTypeface, Float(size), 1, 0)
        defer { sk_font_delete(font) }
        sk_font_set_subpixel(font, true)
        sk_font_set_linear_metrics(font, true)
        sk_font_set_hinting(font, NONE_SK_FONT_HINTING)
        sk_font_set_edging(font, ANTIALIAS_SK_FONT_EDGING)
        let builder = sk_textblob_builder_new()
        defer { sk_textblob_builder_delete(builder) }
        var buffer = sk_textblob_builder_runbuffer_t()
        sk_textblob_builder_alloc_run_pos(builder, font, Int32(glyphs.count), nil, &buffer)
        let ids = buffer.glyphs.assumingMemoryBound(to: UInt16.self)
        let pos = buffer.pos.assumingMemoryBound(to: Float.self)
        var pen = x
        for (k, g) in glyphs.enumerated() {
            ids[k] = g.id
            pos[2 * k] = Float(pen + g.xOffset)
            pos[2 * k + 1] = Float(baseline - g.yOffset)
            pen += g.advance
        }
        guard !p.suppressesDrawing, let blob = sk_textblob_builder_make(builder) else { return }
        defer { sk_textblob_unref(blob) }
        let skPaint = p.makePaint(paint.kind, bounds: bounds)
        sk_canvas_draw_text_blob(p.canvas, blob, 0, 0, skPaint)
        sk_paint_delete(skPaint)
    }
}
