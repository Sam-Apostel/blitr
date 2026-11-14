internal import CSkia

// The scroll edge effect of Liquid Glass bars, and the questions a glass bar asks about its
// surroundings (is content under me, is a tab bar below me).

enum TabBarHostsContentKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True for content shown above a tab bar. A TabView can set this so a navigation stack inside it
    /// does not also put a search field at the bottom; the stack also detects a bar below it from the safe area.
    var tabBarHostsContent: Bool {
        get { self[TabBarHostsContentKey.self] }
        set { self[TabBarHostsContentKey.self] = newValue }
    }
}

enum NavigationGlass {
    /// Whether something (a tab bar) already occupies the bottom of the screen below a stack:
    /// its safe area ends well above the device's own bottom inset.
    @MainActor
    static func barBelow(_ ctx: PlaceContext) -> Bool {
        let device = _currentConfiguration().device
        let deviceBottom = ctx.container.maxY - device.safeArea.bottom
        return ctx.safeRect.maxY < deviceBottom - 8
    }

    /// Whether drawn content (not a full-screen background) overlaps the band `minY..<maxY` (absolute).
    @MainActor
    static func contentOverlaps(_ root: Node, minY: CGFloat, maxY: CGFloat, container: CGRect) -> Bool {
        func visit(_ node: Node) -> Bool {
            if node.children.isEmpty {
                if node is SpacerNode || node is EmptyNode { return false }
                let r = CGRect(origin: node.absoluteOrigin, size: node.frame.size)
                guard r.width > 0.5, r.height > 0.5, r.maxY > minY + 0.5, r.minY < maxY - 0.5 else { return false }
                if r.width >= container.width - 1 && r.height >= container.height * 0.5 { return false }
                return true
            }
            return node.children.contains(where: visit)
        }
        return visit(root)
    }
}

extension Painter {
    /// iOS 26 `.soft` scroll edge effect: the content under a bar is blurred and washed with the
    /// background color, fading out away from `edge`.
    func fillSoftScrollEdge(_ rect: CGRect, edge: VerticalEdge, solidFraction: CGFloat, tint: RGBA, blurRadius: CGFloat) {
        guard rect.width > 0, rect.height > 0 else { return }
        save()
        clip(rect)
        let sigma = Float(blurRadius / 2 * scale)
        saveLayer(LayerOptions(backdropFilter: sk_imagefilter_new_blur(sigma, sigma, CLAMP_SK_SHADER_TILEMODE, nil, nil), bounds: rect))
        fill(Path(rect), with: .color(tint), in: rect)
        let solid = min(max(solidFraction, 0), 1)
        let opaque = RGBA(0, 0, 0, 1), clear = RGBA(0, 0, 0, 0)
        let stops = edge == .top
            ? [GradientStop(color: opaque, location: 0), GradientStop(color: opaque, location: solid), GradientStop(color: clear, location: 1)]
            : [GradientStop(color: clear, location: 0), GradientStop(color: opaque, location: 1 - solid), GradientStop(color: opaque, location: 1)]
        let mask = makePaint(.linear(stops: stops, start: .top, end: .bottom), bounds: rect)
        sk_paint_set_blendmode(mask, DSTIN_SK_BLENDMODE)
        var r = Painter.skRect(rect)
        sk_canvas_draw_rect(canvas, &r, mask)
        sk_paint_delete(mask)
        restore()
        restore()
    }
}

// MARK: - APIs that shape the scroll edge (iOS 26)

extension View {
    /// Like `safeAreaInset`, for a custom bar: content scrolls under it with the scroll edge effect.
    public func safeAreaBar<V: View>(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                                     @ViewBuilder content: () -> V) -> some View {
        safeAreaInset(edge: edge, alignment: alignment, spacing: spacing, content: content)
    }
    public func safeAreaBar<V: View>(edge: HorizontalEdge, alignment: VerticalAlignment = .center, spacing: CGFloat? = nil,
                                     @ViewBuilder content: () -> V) -> some View {
        safeAreaInset(edge: edge, alignment: alignment, spacing: spacing, content: content)
    }
    /// Mirrors the view into the area under a floating sidebar or inspector. Nothing floats over
    /// content on an iPhone, so the view is drawn as is.
    public func backgroundExtensionEffect() -> some View { self }
    public func backgroundExtensionEffect(isEnabled: Bool) -> some View { self }
}
