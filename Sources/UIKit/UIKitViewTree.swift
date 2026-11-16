// A representable's UIKit view tree, drawn: the root takes the size SwiftUI gives it, the tree is laid out
// as UIKit would (UIKitLayout.swift: autoresizing, simple Auto Layout, stack views, app overrides of
// `layoutSubviews`), and each view becomes SwiftUI at its frame:
//
// - its background colour, corner radius (and curve), border, shadow, alpha and transform, clipped when it
//   clips to bounds;
// - its own drawing: `draw(_:)` run with a bitmap CGContext of the view's size current (UIKit and Core
//   Graphics drawing, NSString and NSAttributedString drawing), and its sublayers (CALayer, CAShapeLayer,
//   axial and radial CAGradientLayer, image contents);
// - stock views as their SwiftUI equivalent (labels, image views, activity indicators, blur views, hosted
//   SwiftUI; see `_UIKitRepresentableBody.content(of:)`), and buttons (title, image, configuration style);
// - its subviews, in order, on top.
//
// A tree holding any other UIKit view (a control, a table, a map), a sublayer kind not listed, a mask, or
// Auto Layout the solver cannot place is not drawn: the representable is a placeholder naming it.

import Foundation
import SwiftUI

@MainActor
enum _UIKitViewTree {
    enum Check { case drawable, unsupported(String) }

    /// Whether every visible view and layer in the tree can be drawn, laying it out once to find out.
    static func check(_ root: UIView) -> Check {
        if let reason = unsupported(root) { return .unsupported(reason) }
        let saved = root.frame.size
        let trial = saved.width > 0 && saved.height > 0 ? saved : CGSize(width: _currentCanvasSize().width, height: 200)
        _UIKitLayout.unsolved = []
        root.frame.size = trial
        root._layoutTree()
        defer { _UIKitLayout.unsolved = [] }
        if let view = _UIKitLayout.unsolved.first { return .unsupported("Auto Layout constraints it cannot solve for \(type(of: view))") }
        return .drawable
    }

    private static func unsupported(_ view: UIView) -> String? {
        if view.isHidden || view.alpha <= 0.01 { return nil }
        let kit = _UIKitRepresentableBody.uiKitClass(of: type(of: view))
        switch view {
        case is _HostingControllerView, is _AnyHostingView, is _SwiftUIDrawableView, is UIImageView, is UILabel, is UIActivityIndicatorView,
             is UIVisualEffectView, is UIButton, is UIStackView:
            break
        default:
            guard kit == UIView.self || kit == UIScrollView.self else { return String(describing: kit) }
        }
        if view.mask != nil || view.layer.mask != nil { return "a mask on \(type(of: view))" }
        for layer in view.layer.sublayers ?? [] { if let reason = unsupported(layer) { return reason } }
        for sub in view.subviews { if let reason = unsupported(sub) { return reason } }
        return nil
    }

    private static func unsupported(_ layer: CALayer) -> String? {
        if layer.isHidden { return nil }
        if let gradient = layer as? CAGradientLayer, gradient.type == .conic { return "a conic CAGradientLayer" }
        guard layer is CAShapeLayer || layer is CAGradientLayer || type(of: layer) == CALayer.self else { return String(describing: type(of: layer)) }
        if let contents = layer.contents, !(contents is CGImage) { return "layer contents that are not a CGImage" }
        if layer.mask != nil { return "a layer mask" }
        for sub in layer.sublayers ?? [] { if let reason = unsupported(sub) { return reason } }
        return nil
    }

    /// The tree laid out at `size` and drawn as SwiftUI.
    static func render(_ root: UIView, size: CGSize) -> AnyView {
        root.frame = CGRect(origin: root.frame.origin, size: size)
        root._layoutTree()
        _UIKitLayout.unsolved = []
        return node(root)
    }

    private static func node(_ view: UIView) -> AnyView {
        let size = view.bounds.size
        let layer = view.layer
        let shape = RoundedRectangle(cornerRadius: layer.cornerRadius, style: layer.cornerCurve == .continuous ? .continuous : .circular)
        var parts: [AnyView] = []
        if let background = view.backgroundColor {
            parts.append(AnyView(shape.fill(Color(uiColor: background))))
        } else if let background = layer.backgroundColor {
            parts.append(AnyView(shape.fill(Color(cgColor: background))))
        }
        if let own = content(of: view, size: size) { parts.append(AnyView(own.frame(width: size.width, height: size.height))) }
        if let sublayers = layer.sublayers, !sublayers.isEmpty, let image = bitmap(size, { context in
            for sub in sublayers { draw(sub, in: context) }
        }) {
            parts.append(image)
        }
        for sub in view.subviews where !sub.isHidden && sub.alpha > 0.01 {
            parts.append(AnyView(node(sub).offset(x: sub.frame.minX, y: sub.frame.minY)))
        }
        var result = AnyView(ZStack(alignment: .topLeading) { ForEach(parts.indices, id: \.self) { parts[$0] } }
            .frame(width: size.width, height: size.height, alignment: .topLeading))
        if view.clipsToBounds || layer.masksToBounds { result = AnyView(result.clipShape(shape)) }
        if layer.borderWidth > 0, let border = layer.borderColor {
            result = AnyView(result.overlay(shape.strokeBorder(Color(cgColor: border), lineWidth: layer.borderWidth)))
        }
        if layer.shadowOpacity > 0, let shadow = layer.shadowColor {
            result = AnyView(result.shadow(color: Color(cgColor: shadow).opacity(Double(layer.shadowOpacity)), radius: layer.shadowRadius,
                                           x: layer.shadowOffset.width, y: layer.shadowOffset.height))
        }
        if view.alpha < 1 { result = AnyView(result.opacity(Double(view.alpha))) }
        if !view.transform.isIdentity {
            // UIKit transforms about the centre; SwiftUI's transformEffect about the top-left corner.
            let centred = CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2)
                .concatenating(view.transform).concatenating(CGAffineTransform(translationX: size.width / 2, y: size.height / 2))
            result = AnyView(result.transformEffect(centred))
        }
        return AnyView(result.frame(width: size.width, height: size.height, alignment: .topLeading))
    }

    /// A view's own content: its stock SwiftUI equivalent, a button, or what its `draw(_:)` draws.
    private static func content(of view: UIView, size: CGSize) -> AnyView? {
        if let button = view as? UIButton { return self.button(button) }
        if view is UIStackView { return nil }
        if let stock = _UIKitRepresentableBody.content(of: view, representable: String(describing: type(of: view))) { return stock }
        let kit = _UIKitRepresentableBody.uiKitClass(of: type(of: view))
        guard type(of: view) != kit, _UIKitRepresentableBody.overridesDraw(view) else { return nil }
        return bitmap(size) { _ in view.draw(view.bounds) }
    }

    /// Drawing run with a bitmap context of `size` (at the device's scale) current, as an image of that size.
    private static func bitmap(_ size: CGSize, _ actions: (CGContext) -> Void) -> AnyView? {
        guard size.width >= 0.5, size.height >= 0.5 else { return nil }
        let image = UIGraphicsImageRenderer(size: size).image { actions($0.cgContext) }
        return AnyView(Image(uiImage: image).resizable().frame(width: size.width, height: size.height))
    }

    // MARK: Layers

    private static func draw(_ layer: CALayer, in context: CGContext) {
        guard !layer.isHidden, layer.opacity > 0 else { return }
        let bounds = layer.bounds
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: layer.frame.minX, y: layer.frame.minY)
        let faded = layer.opacity < 1
        if faded {
            context.setAlpha(CGFloat(layer.opacity))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        let outline = CGPath(roundedRect: bounds, cornerWidth: min(layer.cornerRadius, bounds.width / 2), cornerHeight: min(layer.cornerRadius, bounds.height / 2),
                             transform: nil)
        if layer.masksToBounds {
            context.addPath(outline)
            context.clip()
        }
        if let background = layer.backgroundColor {
            context.addPath(outline)
            context.setFillColor(background)
            context.fillPath()
        }
        if let image = layer.contents.flatMap({ $0 as? CGImage }) { context.draw(image, in: bounds) }
        if let gradient = layer as? CAGradientLayer { draw(gradient, in: context) }
        if let shape = layer as? CAShapeLayer { draw(shape, in: context) }
        for sub in layer.sublayers ?? [] { draw(sub, in: context) }
        if layer.borderWidth > 0, let border = layer.borderColor {
            let inset = layer.borderWidth / 2
            context.addPath(CGPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), cornerWidth: max(0, min(layer.cornerRadius, bounds.width / 2) - inset),
                                   cornerHeight: max(0, min(layer.cornerRadius, bounds.height / 2) - inset), transform: nil))
            context.setStrokeColor(border)
            context.setLineWidth(layer.borderWidth)
            context.strokePath()
        }
        if faded { context.endTransparencyLayer() }
    }

    private static func draw(_ layer: CAGradientLayer, in context: CGContext) {
        let colors = (layer.colors ?? []).compactMap { $0 as? CGColor }
        guard !colors.isEmpty else { return }
        let locations = layer.locations?.map { CGFloat($0.doubleValue) }
        let made: CGGradient? = if let locations, locations.count == colors.count {
            locations.withUnsafeBufferPointer { CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: $0.baseAddress) }
        } else {
            CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil)
        }
        guard let gradient = made else { return }
        let b = layer.bounds
        func point(_ unit: CGPoint) -> CGPoint { CGPoint(x: b.minX + unit.x * b.width, y: b.minY + unit.y * b.height) }
        let start = point(layer.startPoint), end = point(layer.endPoint)
        context.saveGState()
        context.clip(to: b)
        if layer.type == .radial {
            let radius = max(abs(end.x - start.x), abs(end.y - start.y))
            context.drawRadialGradient(gradient, startCenter: start, startRadius: 0, endCenter: start, endRadius: radius, options: [.drawsAfterEndLocation])
        } else {
            context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        context.restoreGState()
    }

    private static func draw(_ layer: CAShapeLayer, in context: CGContext) {
        guard let path = layer.path else { return }
        if let fill = layer.fillColor {
            context.addPath(path)
            context.setFillColor(fill)
            context.fillPath(using: layer.fillRule == .evenOdd ? .evenOdd : .winding)
        }
        guard let stroke = layer.strokeColor, layer.lineWidth > 0, layer.strokeEnd > layer.strokeStart else { return }
        let trimmed = layer.strokeStart > 0 || layer.strokeEnd < 1
            ? SwiftUI.Path(path).trimmedPath(from: max(0, layer.strokeStart), to: min(1, layer.strokeEnd)).cgPath : path
        context.addPath(trimmed)
        context.setStrokeColor(stroke)
        context.setLineWidth(layer.lineWidth)
        context.setLineCap(layer.lineCap == .round ? .round : layer.lineCap == .square ? .square : .butt)
        context.setLineJoin(layer.lineJoin == .round ? .round : layer.lineJoin == .bevel ? .bevel : .miter)
        context.setMiterLimit(layer.miterLimit)
        if let dash = layer.lineDashPattern, !dash.isEmpty {
            context.setLineDash(phase: layer.lineDashPhase, lengths: dash.map { CGFloat($0.doubleValue) })
        }
        context.strokePath()
    }

    // MARK: Buttons

    /// A button's title and image; with a configuration, in the matching SwiftUI button style.
    private static func button(_ button: UIButton) -> AnyView {
        let configuration = button.configuration
        let title = configuration?.attributedTitle.map { String($0.characters) } ?? button.currentTitle
        let image = button.currentImage
        let label = HStack(spacing: configuration?.imagePadding ?? 0) {
            if let image { Image(uiImage: image) }
            if let title { Text(title) }
        }
        guard let configuration else {
            let font = button.titleLabel?.font ?? .systemFont(ofSize: 17)
            return AnyView(label.font(Font(font)).foregroundStyle(Color(uiColor: button.currentTitleColor))
                .opacity(button.isEnabled ? 1 : 0.35)
                .frame(maxWidth: .infinity, maxHeight: .infinity))
        }
        let filling = label.frame(maxWidth: .infinity, maxHeight: .infinity)
        let styled: AnyView
        switch configuration.style {
        case .filled, .borderedProminent: styled = AnyView(Button {} label: { filling }.buttonStyle(.borderedProminent))
        case .tinted, .borderedTinted, .gray, .bordered: styled = AnyView(Button {} label: { filling }.buttonStyle(.bordered))
        case .plain: styled = AnyView(Button {} label: { label }.buttonStyle(.borderless))
        case .glass: styled = AnyView(Button {} label: { filling }.buttonStyle(.glass))
        case .prominentGlass: styled = AnyView(Button {} label: { filling }.buttonStyle(.glassProminent))
        }
        let size: ControlSize = switch configuration.buttonSize {
        case .mini: .mini
        case .small: .small
        case .medium: .regular
        case .large: .large
        }
        var result = AnyView(styled.controlSize(size).tint(Color(uiColor: configuration.baseBackgroundColor ?? button.tintColor)).disabled(!button.isEnabled))
        if let foreground = configuration.baseForegroundColor { result = AnyView(result.foregroundStyle(Color(uiColor: foreground))) }
        return result
    }
}

/// A view tree laid out at the size SwiftUI gives it (see the top of this file).
struct _UIKitViewTreeView: View {
    let root: UIView
    var body: some View {
        GeometryReader { proxy in
            MainActor.assumeIsolated { _UIKitViewTree.render(root, size: proxy.size) }
        }
    }
}

/// A representable's size: `sizeThatFits(_:uiView:context:)` when it gives one; else, for a view tree, the
/// view's intrinsicContentSize in each dimension it has one (the view grows past it when its content hugging
/// priority is `.defaultLow` or lower, and shrinks below it when its compression resistance is), and the
/// proposed size in the others; else the content's own size.
struct _RepresentableLayout<Content: View>: View {
    let sizeThatFits: @MainActor (ProposedViewSize) -> CGSize?
    let intrinsic: UIView?
    let content: Content
    init(sizeThatFits: @escaping @MainActor (ProposedViewSize) -> CGSize?, intrinsic: UIView?, @ViewBuilder content: () -> Content) {
        self.sizeThatFits = sizeThatFits
        self.intrinsic = intrinsic
        self.content = content()
    }
    var body: some View {
        RepresentableSizing(sizeThatFits: sizeThatFits, intrinsic: intrinsic) { content }
    }
}

private struct RepresentableSizing: Layout {
    let sizeThatFits: @MainActor (ProposedViewSize) -> CGSize?
    let intrinsic: UIView?

    private func size(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (CGSize, own: Bool) {
        if let custom = sizeThatFits(proposal) { return (custom, true) }
        let child = subviews.first?.sizeThatFits(proposal) ?? .zero
        guard let view = intrinsic else { return (child, false) }
        let i = view.intrinsicContentSize
        func axis(_ intrinsic: CGFloat, _ proposed: CGFloat?, _ childValue: CGFloat, _ axis: NSLayoutConstraint.Axis) -> CGFloat {
            guard intrinsic >= 0 else { return childValue }
            let lo = view.contentCompressionResistancePriority(for: axis) > .defaultLow ? intrinsic : 0
            let hi = view.contentHuggingPriority(for: axis) > .defaultLow ? intrinsic : .infinity
            let base = proposed.flatMap { $0.isFinite ? $0 : nil } ?? intrinsic
            return min(max(base, lo), hi)
        }
        return (CGSize(width: axis(i.width, proposal.width, child.width, .horizontal),
                       height: axis(i.height, proposal.height, child.height, .vertical)), true)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { size(proposal, subviews).0 }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let own = size(proposal, subviews).own
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: own ? ProposedViewSize(bounds.size) : proposal)
    }
}
