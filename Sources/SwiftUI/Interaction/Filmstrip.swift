internal import CSkia

// `--filmstrip <file.png>`: the captured frames side by side, each with a caption (the step that led
// to it, or its time in an animation).

@MainActor
enum Filmstrip {
    static let margin: CGFloat = 16
    static let gap: CGFloat = 16
    static let captionGap: CGFloat = 8
    static let captionSize: CGFloat = 12
    static let cornerRadius: CGFloat = 6

    static func compose(_ cells: [(image: FrameImage, caption: String)], pixelsPerPoint: Double, scheme: ColorScheme,
                        environment: EnvironmentValues, runtime: Runtime, to path: String) throws {
        let s = CGFloat(max(0.25, pixelsPerPoint))
        let cellWidth = CGFloat(cells.map(\.image.width).max() ?? 1) / s
        let cellHeight = CGFloat(cells.map(\.image.height).max() ?? 1) / s
        // Captions are ordinary Text, laid out by the renderer itself.
        let wasRecording = CaptureInfo.isRecording
        CaptureInfo.isRecording = false
        defer { CaptureInfo.isRecording = wasRecording }
        var env = environment
        env.colorScheme = scheme
        let ctx = ResolveContext(env: env, path: IdentityPath(components: ["filmstrip"]), runtime: runtime)
        var captions: [(node: Node, size: CGSize)] = []
        for (i, cell) in cells.enumerated() {
            let text = Text(verbatim: cell.caption).font(.system(size: captionSize, weight: .medium))
                .foregroundStyle(Color(SystemColor.secondaryLabel)).multilineTextAlignment(.center).lineLimit(3)
            let node = resolveSingle(text, ctx.child(i))
            captions.append((node, node.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil))))
        }
        let captionHeight = captions.map(\.size.height).max() ?? 0
        let size = CGSize(width: margin * 2 + cellWidth * CGFloat(cells.count) + gap * CGFloat(cells.count - 1),
                          height: margin * 2 + cellHeight + (captionHeight > 0 ? captionGap + captionHeight : 0))
        let pixelWidth = Int((size.width * s).rounded(.up)), pixelHeight = Int((size.height * s).rounded(.up))
        guard pixelWidth <= 32767, pixelHeight <= 32767 else {
            throw RenderError("--filmstrip: \(cells.count) frames make a strip \(pixelWidth) pixels wide, which is too large. Use fewer snapshots, --filmstrip-frames <n> or a smaller --filmstrip-scale.")
        }
        var info = sk_imageinfo_t(colorspace: sk_colorspace_new_srgb(), width: Int32(pixelWidth), height: Int32(pixelHeight),
                                  colorType: RGBA_8888_SK_COLORTYPE, alphaType: PREMUL_SK_ALPHATYPE)
        guard let surface = sk_surface_new_raster(&info, 0, nil), let canvas = sk_surface_get_canvas(surface) else {
            throw RenderError("--filmstrip: could not allocate a \(pixelWidth)x\(pixelHeight) surface")
        }
        defer { sk_surface_unref(surface) }
        let background = scheme == .dark ? RGBA(0.11, 0.11, 0.118, 1) : RGBA(0.949, 0.949, 0.969, 1)
        sk_canvas_clear(canvas, Painter.skColor(background))
        let painter = Painter(canvas: canvas, scale: s, surface: surface)
        painter.scale(s, s)
        let container = CGRect(origin: .zero, size: size)
        var sampling = sk_sampling_options_t(fMaxAniso: 0, fUseCubic: false, fCubic: sk_cubic_resampler_t(fB: 0, fC: 0),
                                             fFilter: LINEAR_SK_FILTER_MODE, fMipmap: NONE_SK_MIPMAP_MODE)
        for (i, cell) in cells.enumerated() {
            let x = margin + (cellWidth + gap) * CGFloat(i)
            let w = CGFloat(cell.image.width) / s, h = CGFloat(cell.image.height) / s
            let rect = CGRect(x: x + (cellWidth - w) / 2, y: margin, width: w, height: h)
            if let image = FramePixels.makeImage(cell.image) {
                painter.save()
                painter.clip(Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous))
                var src = sk_rect_t(left: 0, top: 0, right: Float(cell.image.width), bottom: Float(cell.image.height))
                var dst = Painter.skRect(rect)
                sk_canvas_draw_image_rect(canvas, image, &src, &dst, &sampling, nil)
                painter.restore()
                sk_image_unref(image)
            }
            painter.stroke(Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous),
                           with: .color(SystemColor.separator.resolve(scheme)), style: StrokeStyle(lineWidth: 1 / s), in: rect)
            let caption = captions[i]
            caption.node.place(at: CGPoint(x: x + (cellWidth - caption.size.width) / 2, y: margin + cellHeight + captionGap), size: caption.size,
                               PlaceContext(origin: .zero, container: container, safeRect: container, scale: s))
            caption.node.draw(painter)
        }
        try FramePixels.writePNG(surface: surface, to: path)
    }
}

/// `--full-content`: implemented with the scroll capture (ScrollCapture.swift).
@MainActor
enum FullContent {
    static func render(host: RenderHost, to path: String) throws {
        throw RenderError("--full-content is not available yet")
    }
}
